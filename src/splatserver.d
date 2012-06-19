/*
    Copyright (C) 2007 Christopher E. Miller
    
    This software is provided 'as-is', without any express or implied
    warranty.  In no event will the authors be held liable for any damages
    arising from the use of this software.
    
    Permission is granted to anyone to use this software for any purpose,
    including commercial applications, and to alter it and redistribute it
    freely, subject to the following restrictions:
    
    1. The origin of this software must not be misrepresented; you must not
       claim that you wrote the original software. If you use this software
       in a product, an acknowledgment in the product documentation would be
       appreciated but is not required.
    2. Altered source versions must be plainly marked as such, and must not be
       misrepresented as being the original software.
    3. This notice may not be removed or altered from any source distribution.
*/
module splatserver;
import std.socket;
alias std.socket.InternetAddress NetAddr;
import std.string;
alias std.string.toUpper strtoupper;
alias std.string.indexOf strfindchar;
alias std.string.icmp stricompare;
import std.ascii;
alias std.ascii.isAlphaNum charisalnum;
alias std.ascii.isDigit charisdigit;
import std.stdio;
import simpleserver.splat;

void writestrline(char[] s)
{
    writefln("%s", s);
}

class IrcClientSocket: AsyncTcpSocket
{
    char[] nick;
    SocketQueue queue;
    
    
    char[] fulladdress() // getter
    {
        return nick ~ "!user@foo.bar";
    }
    
    
    bool allowed() // getter
    {
        return 0 != nick.length;
    }
    
    
    void sendLine(char[] s)
    {
        queue.send(s ~ "\r\n");
    }
    
    
    void onLine(char[] line)
    {
        long i;
        
        char[] cmd;
        i = strfindchar(line, ' ');
        if(-1 == i)
        {
            cmd = line;
            line = null;
        }
        else
        {
            cmd = line[0 .. i];
            line = line[i + 1 .. line.length];
        }
        cmd = strtoupper(cmd);
        
        // Handle commands...
        if(!allowed)
        {
            switch(cmd)
            {
                case "NICK":
                    for(i = 0; i != line.length; i++)
                    {
                        if(!charisalnum(line[i]) && '_' != line[i]
                            && '[' != line[i] && ']' != line[i] && '-' != line[i])
                            break;
                    }
                    line = line[0 .. i];
                    if(!line.length || charisdigit(line[0]))
                    {
                        sendLine(cast(char[])":foo.bar 432  :Bad nickname!");
                    }
                    else
                    {
                        foreach(client; clients)
                        {
                            if(!stricompare(client.nick, line))
                            {
                                sendLine(cast(char[])":foo.bar 433  :That nickname is in use!");
                                goto nick_done;
                            }
                        }
                        
                        nick = line.dup;
                        
                        sendLine(":foo.bar 001 " ~ nick ~ " :Welcome to SPLAT!");
                        sendLine(":foo.bar 002 " ~ nick ~ " :Your host is foo.bar");
                        sendLine(":foo.bar 003 " ~ nick ~ " :This server was created Fri Dec 8 2006 at 14:00:00 GMT");
                        sendLine(":foo.bar 422 " ~ nick ~ " :No MOTD");
                        
                        clients[this] = this;
                        
                        broadcast(":" ~ fulladdress ~ " JOIN #splat");
                        sendNamesList();
                    }
                    nick_done:
                    break;
                
                case "QUIT":
                    clients.remove(this);
                    closeSocket();
                    break;
                
                default: ;
            }
        }
        else // allowed
        {
            switch(cmd)
            {
                case "QUIT":
                    clients.remove(this);
                    closeSocket();
                    broadcast(":" ~ fulladdress ~ " QUIT " ~ line);
                    if(!line.length || ":" == line)
                    {
                        broadcast(":" ~ fulladdress ~ " QUIT");
                    }
                    else
                    {
                        if(':' == line[0])
                            line = line[1 .. line.length];
                        broadcast(":" ~ fulladdress ~ " QUIT :Quit: " ~ line);
                    }
                    break;
                case "PRIVMSG":
                    i = strfindchar(line, ' ');
                    if(-1 != i)
                    {
                        if(!stricompare(line[0 .. i], "#splat"))
                        {
                            line = line[i + 1 .. line.length];
                            if(line.length)
                            {
                                broadcastButOne(":" ~ fulladdress ~ " PRIVMSG #splat " ~ line, this);
                            }
                        }
                        else
                        {
                            cantdothat();
                        }
                    }
                    break;
                
                case "NOTICE":
                    cantdothat();
                    break;
                
                case "NAMES":
                    if(!stricompare(line, "#splat"))
                    {
                        sendNamesList();
                    }
                    break;
                
                case "PING":
                    sendLine(":foo.bar PONG foo.bar " ~ line);
                    break;
                
                default: ;
            }
        }
    }
    
    
    void sendNamesList()
    {
        char[] s;
        s = ":foo.bar 353 " ~ nick ~ " = #splat :";
        foreach(client; clients)
        {
            if(client.allowed)
            {
                s ~= client.nick;
                s ~= " ";
            }
        }
        sendLine(s);
        sendLine(":foo.bar 366 " ~ nick ~ " #splat :End of /NAMES list.");
    }
    
    
    void cantdothat()
    {
        sendLine(":the.server PRIVMSG " ~ nick ~ " :You can't do that!");
    }
    
    
    void gotReadEvent()
    {
        byte[] peek;
        find_line:
        peek = cast(byte[])queue.peek();
        foreach(idx, b; peek)
        {
            if('\r' == b || '\n' == b)
            {
                if(!idx)
                {
                    queue.receive(1); // Remove from queue.
                    goto find_line;
                }
                queue.receive(cast(uint)idx + 1); // Remove from queue.
                onLine(cast(char[])peek[0 .. idx]);
                goto find_line;
            }
        }
    }
    
    
    void netEvent(Socket sock, EventType type, int err)
    {
        if(err)
        {
            clients.remove(this);
            closeSocket();
            if(allowed)
                broadcast(":" ~ fulladdress ~ " QUIT :Connection error");
            return;
        }
        
        switch(type)
        {
            case EventType.CLOSE:
                clients.remove(this);
                closeSocket();
                if(allowed)
                    broadcast(":" ~ fulladdress ~ " QUIT :Connection closed");
                break;
            
            case EventType.READ:
                queue.readEvent();
                if(queue.receiveBytes > 1024 * 4)
                {
                    clients.remove(this);
                    closeSocket();
                    queue.reset();
                    if(allowed)
                        broadcast(":" ~ fulladdress ~ " QUIT :Excess flood");
                }
                else
                {
                    gotReadEvent();
                }
                break;
            
            case EventType.WRITE:
                if(queue.sendBytes > 1024 * 8)
                {
                    clients.remove(this);
                    closeSocket();
                    queue.reset();
                    if(allowed)
                        broadcast(":" ~ fulladdress ~ " QUIT :Excess send-queue");
                }
                else
                {
                    queue.writeEvent();
                }
                break;
            
            default: ;
        }
    }
    
    alias close closeSocket;
}


class IrcListenSocket: AsyncTcpSocket
{
    override IrcClientSocket accepting()
    {
        return new IrcClientSocket();
    }
    
    void netEvent(Socket sock, EventType type, int err)
    {
        if(!err)
        {
            IrcClientSocket nsock;
            nsock = cast(IrcClientSocket)sock.accept();
            writestrline(cast(char[])"Connection accepted from " ~ nsock.remoteAddress.toString());
            nsock.queue = new SocketQueue(nsock);
            nsock.event(EventType.READ | EventType.WRITE | EventType.CLOSE, &nsock.netEvent);
        }
    }
}

IrcClientSocket[IrcClientSocket] clients;

void broadcast(char[] s)
{
    foreach(client; clients)
    {
        client.sendLine(s);
    }
}


void broadcastButOne(char[] s, IrcClientSocket except)
{
    foreach(client; clients)
    {
        if(client !is except)
            client.sendLine(s);
    }
}


void splat()
{
    bool done = false;
    scope lsock = new IrcListenSocket;
    scope lsockaddr = new NetAddr(NetAddr.ADDR_ANY, 1667); // Not standard IRC port.. not standard IRC server.
    lsock.bind(lsockaddr);
    lsock.listen(10);
    lsock.event(EventType.ACCEPT, &lsock.netEvent);
    writestrline(cast(char[])"Server ready on port 1667");
    do
    {
        try
        {
            simpleserver.splat.run();
            done = true; // run returned upon request.
        }
        catch(Throwable o)
        {
            writestrline(cast(char[])"Error: " ~ o.toString());
        }
    }
    while(!done);
}