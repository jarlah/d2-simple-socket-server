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

class IrcClientSocket: AsyncTcpSocket
{
    char[] nick = cast(char[])"unknown";
    
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
    	clients[this] = this;
    	sendLine(line);
    	std.stdio.writeln(clients);
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
            IrcClientSocket nsock = cast(IrcClientSocket)sock.accept();
            writeln("Connection accepted from " ~ nsock.remoteAddress.toString());
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


void splat()
{
	try {
		scope lsock = new IrcListenSocket;
		scope lsockaddr = new NetAddr(NetAddr.ADDR_ANY, 1667); // Not standard IRC port.. not standard IRC server.
	    lsock.bind(lsockaddr);
	    lsock.listen(10);
	    lsock.event(EventType.ACCEPT, &lsock.netEvent);
	    writeln("Server ready on port 1667");
        simpleserver.splat.run();
    } catch(Throwable o) {
        writeln("Error: " ~ o.toString());
    }
}