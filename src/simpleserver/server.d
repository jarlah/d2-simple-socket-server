/*
D2 Simple Socket Server.

Copyright (C) 2012 Jarl André Hübenthal

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
*/

module simpleserver.server;
import std.conv, std.socket, std.concurrency, std.socketstream, std.stdio, core.thread, std.stream, std.string, std.ascii, std.base64;
import simpleserver.logger;

ILogger logger;

abstract class Server: Thread {
	this(void delegate() fn){
		super(fn);
	}
	void startServer();
	void startServer(ref Server server);
	void startAdminServer();
	void disableLog();
	void setHost(string host);
	void setPort(int port);
	void setAdminPort(int port);
	void setName(string name);
	void setAdminName(string name);
	void setAuthenticator(string handlerClass);
	void setCommandHandler(string handlerClass);
	void setSocketHandler(string handlerClass);
	void setClientData(string clientData);
	string getVersionNumber();
	ulong getNumberOfClients();
}

Server createSimpleServer()
{
	return new SimpleServer();
}

import simpleserver.splat;

void broadcast(char[] s)
{
    foreach(client; clients)
    {	
        client.sendLine(s);
    }
}

class SimpleClientSocket: AsyncTcpSocket
{
    char[] nick;
    
    SocketQueue queue;
    
    IClientCommandHandler commandHandler;
    
    Authenticator authHandler;
    
    IClientHandler clientHandler;
    
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
    
    string username, password, lastCommand;
    
    void onLine(char[] line)
    {
    	if(!allowed && authHandler !is null){
    		if(lastCommand is null){
				sendCommand(":AUTH NICK");
			}else if(":AUTH NICK" == lastCommand){
    			username = to!string(line);
    			sendCommand(":AUTH PASS");
    		}else if(":AUTH PASS" == lastCommand){
    			password = to!string(line);
    			validateCredentials();
    			lastCommand = null;
    		}
    	}else if(!allowed && authHandler is null){
    		nick = cast(char[])"unknown";
    		goto handle_command;
    	}else if(allowed){
    		handle_command:
    		commandHandler.handleCommand(clientHandler,to!string(line));
    	}else{
    		sendLine(cast(char[])":AUTH ERR: Not logged in");
    	}
    }
    
    void validateCredentials(){
    	if(true == authHandler.isAuthorized(clientHandler,username,password))
    		nick = cast(char[])username;
    	else
    		logger.error("Wrong credentials");
    }
    
    void sendCommand(string cmd){
    	sendLine(cast(char[])cmd);
    	lastCommand =cmd;
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


class SimpleListenSocket: AsyncTcpSocket
{
	private SimpleServer parent;
	private IClientCommandHandler commandHandler;
	private Authenticator authHandler;
	private int MAX;
	
	this(SimpleServer p){
		this.parent = p;
		
		logger.info("Starting "~parent.name); 
		
		auto chc = parent.commandHandlerClass;
		
		enforce(chc);
		logger.info("Loading handler class "~chc);
		commandHandler = cast(IClientCommandHandler) Object.factory(chc);
		enforce(commandHandler);
		
		commandHandler.setServer(parent.service);
		
		auto ahc = parent.authHandlerClass;
		
		if(ahc !is null){
			logger.info("Loading authenticator class "~ahc);
			authHandler = cast(Authenticator) Object.factory(ahc);
			enforce(authHandler);
		}
		
		MAX = parent.MAX;
	}
	
    override SimpleClientSocket accepting()
    {
        return new SimpleClientSocket();
    }
    
    void netEvent(Socket sock, EventType type, int err)
    {
        if(!err)
        {
        	if(clients.length < MAX){
	            SimpleClientSocket nsock = cast(SimpleClientSocket)sock.accept();
	            
	            nsock.queue = new SocketQueue(nsock);
	            nsock.commandHandler = commandHandler;
	            nsock.authHandler = authHandler;
	            if(authHandler !is null)
	            	nsock.sendCommand(":AUTH NICK");
	            auto ahc = parent.socketHandlerClass;
	            logger.info("Loading client handler class "~ahc);
	            IClientHandler ch = cast(IClientHandler) Object.factory(ahc);
	            
	            auto dc = parent.clientDataClass;
	            logger.info("Loading client data class "~dc);
	            ClientData _dc = cast(ClientData) Object.factory(dc);
	            
	            ch.setup(nsock,_dc);
	            
	            nsock.clientHandler = ch;

	            nsock.event(EventType.READ | EventType.WRITE | EventType.CLOSE, &nsock.netEvent);
	            
	            commandHandler.gotConnected(ch);
            }else{
            	commandHandler.gotRejected(sock);
            }
        }
    }
}
	
SimpleClientSocket[SimpleClientSocket] clients;

class SimpleServer: Server{
	public:
	this(){
		super( &run );
	}
	
	override void startServer(){
		Server casted = cast(Server)this;
		startServer(casted);
	}
	
	override void startServer(ref Server server){
		this.service = server;
		isServerStarted = true;
		this.start();
	}
	
	void startAdminServer() in {
		enforce(isServerStarted is true, "Admin service cannot be started before the main service");
		enforce(adminServer is null, "Admin service is already started");
	} body {
		adminServer = createSimpleServer();
		adminServer.setCommandHandler("simpleserver.server.AdminClientCommandHandler");
		adminServer.setAuthenticator("simpleserver.server.AdminAuthenticator");
		adminServer.setPort(adminPort);
		adminServer.setHost(host);
		adminServer.setName(adminName);
		adminServer.disableLog();
		adminServer.startServer(cast(Server)this.service);
	}
	
	void run(){
		try{
			initLogger();
			scope lsock = new SimpleListenSocket(this);
			scope lsockaddr = new InternetAddress(cast(const(char[]))host, to!short(port)); // Not standard IRC port.. not standard IRC server.
			lsock.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, socketTimeout);
			lsock.bind(lsockaddr);
		    lsock.listen(backlog);
		    lsock.blocking = blocking;
		    lsock.event(EventType.ACCEPT, &lsock.netEvent);
		    logger.info("Server ready on port "~to!string(port));
	        simpleserver.splat.run();
        }catch(Throwable o){
        	logger.error(o.toString());
        }
	}
	
	public void initLogger(){
		if(doNotLog == false){
			logger = getSimpleLogger();
		}else{
			logger = getNoLogger();
		}
	}
	
	override void setCommandHandler(string handlerClass) {
		this.commandHandlerClass = handlerClass;
	}
	
	override void setSocketHandler(string handlerClass) {
		this.socketHandlerClass = handlerClass;
	}
	
	override void setAuthenticator(string handlerClass) {
		this.authHandlerClass = handlerClass;
	}
	
	override void setName(string name) {
		this.name = name;
	}
	
	override void setClientData(string clientData) {
		this.clientDataClass = clientData;
	}
	
	void setPort(int port) in {
		assert(port>0,"Port > 0");
	} body {
		this.port = port;
	}
	
	void setHost(string host) in {
		enforce("Host cannot be null",host);
	} body {
		this.host = host;
	}
	
	void setMax(int max) in {
		assert(max>1, "Max be larger than 0");
	} body {
		this.MAX = max;
	}
	
	void setBacklog(int bl) in {
		assert(bl>1, "Backlog be larger than 0");
	} body {
		this.backlog = bl;
	}
	
	void setBlocking(bool boolean)
	{
		this.blocking = boolean;
	}
	
	void setSocketTimeout(std.socket.Duration dur) {
		this.socketTimeout = dur;
	}
	
	string getVersionNumber(){
		return this.versionNumber;
	}
	
	ulong getNumberOfClients(){
		return handlers.length;
	}
	
	override void disableLog(){
		doNotLog = true;
	}
	
	void setAdminPort(int port) in {
		assert(port !is this.port,"Admin port number cannot be the same as the server port number");
	} body {
		this.adminPort = port;
	}
	
	void setAdminName(string name){
		this.adminName = name;
	}
	
	private:
	auto versionNumber 			= "1.0.1";
	auto MAX 					= 120;
	auto host 					= "localhost";
	auto port 					= 1234;
	auto adminPort 				= 2345;
	auto name 					= "SimpleServer";
	auto adminName 				= "SimpleServer Admin";
	auto blocking 				= false;
	auto backlog 				= 60;
	auto doNotLog 				= false;
	auto socketTimeout 			= dur!"seconds"(60);
	auto socketHandlerClass 	= "simpleserver.server.DefaultClientHandler";
	auto isServerStarted 		= false;
	string commandHandlerClass	= null;
	string authHandlerClass		= null;
	string clientDataClass 		= null;
	Server service				= null;
	Server adminServer			= null;
	IClientHandler[Socket] handlers;
}

abstract class AbstractClientCommandHandler: IClientCommandHandler {
	private Server server;
	this(){}
	abstract void handleCommand(IClientHandler socket, string command);
	void gotConnected(IClientHandler socket){};
	void gotRejected(Socket socket){};
	void closingConnection(IClientHandler socket){};
	void lostConnection(IClientHandler socket){};
	void setServer(ref Server server){ this.server = server; }
	Server getServer(){ return this.server; }
}

interface IClientCommandHandler {
	void gotConnected(IClientHandler handler);
	void gotRejected(Socket socket);
	void closingConnection(IClientHandler handler);
	void lostConnection(IClientHandler handler);
	void handleCommand(IClientHandler handler, string command);
	void setServer(ref Server server);
	Server getServer();
}

class DefaultClientHandler: AbstractClientHandler {
	this(){}
}

abstract class AbstractClientHandler: IClientHandler {
	public:
	this(){}
	
	void setup(ref SimpleClientSocket sock, ClientData cd){
		this.socket = sock;
		this.clientData = cd;
		this._remoteAddress = remoteAddress();
		this._localAddress = localAddress();
	}
	
	void sendString(string msg){
		socket.sendLine(cast(char[])msg);
	}
	
	string remoteAddress(){
		string toreturn = _remoteAddress;
		if(toreturn is null)
			toreturn = to!string(socket.remoteAddress().toString());
		return toreturn;
	}
	
	string localAddress(){
		string toreturn = _localAddress;
		if(toreturn is null)
			toreturn = to!string(socket.localAddress().toString());
		return toreturn;
	}
	
	void close(){
		socket.close();
	}
	
	Socket getSocket(){
		return socket;
	}
	
	ClientData getClientData(){
		if(clientData is null)
			throw new Exception("There are no client data object on the client handler!");
		return clientData;
	}
	
	private:
	SimpleClientSocket socket;
	ClientData clientData;
	string _remoteAddress;
	string _localAddress;
}

interface IClientHandler {
	void 		sendString(string msg);
	string 		remoteAddress();
	string 		localAddress();
	void 		setup(ref SimpleClientSocket socket, ClientData cd) 
	in { assert(cd !is null); }
	Socket 		getSocket();
	ClientData 	getClientData();
	void 		close();
}

interface ClientData {}

interface Authenticator { 
	bool isAuthorized(IClientHandler handler, string username, string password); 
}

private:
class AdminAuthenticator: Authenticator {
	bool isAuthorized(IClientHandler clientHandler, string user, string pass){
		return user == pass;
	}
}

class AdminClientCommandHandler: AbstractClientCommandHandler {
	this(){
		super();
	}
	
	override void handleCommand(IClientHandler clientHandler, string command){
		logger.info("Got message: "~command);
		if("version" == command)
			clientHandler.sendString("+OK "~getServer().getVersionNumber());
		else if("noclient server" == command)
			clientHandler.sendString("+OK "~to!string(getServer().getNumberOfClients()));
		else
			clientHandler.sendString("-ERR Unknown command");
	}
	
	override void closingConnection(IClientHandler socket){
		logger.info("Closing socket from "~socket.remoteAddress());
	}
	
	override void lostConnection(IClientHandler socket){
		logger.info("Lost connection from "~socket.remoteAddress());
	}
}