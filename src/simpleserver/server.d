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
		if(doNotLog == false){
			logger = getSimpleLogger();
		}else{
			logger = getNoLogger();
		}
		
		logger.info("Starting "~name); 
		
		enforce(commandHandlerClass);
		logger.info("Loading handler class "~commandHandlerClass);
		commandHandler = cast(IClientCommandHandler) Object.factory(commandHandlerClass);
		enforce(commandHandler);
		commandHandler.setServer(service);
		
		if(authHandlerClass !is null){
			logger.info("Loading authenticator class "~authHandlerClass);
			authHandler = cast(Authenticator) Object.factory(authHandlerClass);
			enforce(authHandler);
		}
		
		Socket listener = new TcpSocket;
		assert(listener.isAlive);
		
		listener.blocking = blocking;
		listener.bind(new InternetAddress(cast(const(char[]))host,to!ushort(port)));
		listener.listen(backlog);
			
		logger.info("Listening on port "~to!string(port));
		
		SocketSet sset = new SocketSet(MAX+1);
		
		for (;; sset.reset())
		{
			sset.add(listener);

			foreach (Socket each; handlers.keys)
			{
				sset.add(each);
			}
			
			Socket.select(sset,null,null);
			
			int i;

			for (i = 0;; i++)
			{
				next:
				if (i == handlers.length)
					break;
					
				auto sock = handlers.keys[i];
				if (sset.isSet(sock))
				{
					auto handler = handlers[sock];
					enforce(handler);

					scope(failure){
						closeSocket(handler);
						goto next;
					}

					string read = to!string(handler.readLine());
					if(read.length==0){
						closeSocket(handler);
						goto next;
					}

					logger.info(to!string("Received "~to!string(read.length)~"bytes from "~handler.remoteAddress()~": \""~read~"\""));

					try{
						commandHandler.handleCommand(handler, read);
					}catch(Exception e){
						logger.error(e.toString());
						throw e;
					}
				}
			}
			
			if (sset.isSet(listener))
			{
				Socket sn;
				if (handlers.length < MAX)
				{
					scope(failure)
						goto close;

					sn = listener.accept();
					sn.setOption(SocketOptionLevel.SOCKET, SocketOption.RCVTIMEO, socketTimeout);
					assert(sn.isAlive);
					assert(listener.isAlive);

					logger.info("Loading socket handler class "~socketHandlerClass);
					IClientHandler handler = cast(IClientHandler)Object.factory(socketHandlerClass);
					ClientData clientData = null;
					if(clientDataClass !is null){
						logger.info("Loading client data class "~clientDataClass);
						clientData = cast(ClientData)Object.factory(clientDataClass);
					}
					
					handler.setup(sn, clientData);

					if(authHandler !is null){
						bool authorized;
						try{
							authorized = authHandler.askAuthorisation(handler);
						}catch(Exception e){
							logger.error(e.toString());
							authorized = false;
						}
						if(authorized){
							logger.info("User authenticated");
						}else{
							logger.error("User failed to authenticate");
							goto close;
						}
					}else{
						handler.sendString(Authenticator.AUTH_OK~": Welcome.");
					}

					logger.info("Connection from "~handler.remoteAddress()~" established.");
					commandHandler.gotConnected(handler);
					handlers[sn] = handler;
					logger.info("\tTotal connections: "~to!string(handlers.length));
				}
				else
				{
					sn = listener.accept();
					assert(sn.isAlive);
					commandHandler.gotRejected(sn);
					logger.warning("Rejected connection; too many connections.");

					close:
					sn.close();
					assert(!sn.isAlive);
					assert(listener.isAlive);
				}
			}
		}
	}
	
	IClientCommandHandler getCommandHandler(){
		return this.commandHandler;
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
	Authenticator authHandler	= null;
	Server service				= null;
	Server adminServer			= null;
	IClientCommandHandler commandHandler;
	IClientHandler[Socket] handlers;
	
	void closeSocket(IClientHandler handler){
		commandHandler.closingConnection(handler);
		try
		{
			logger.warning("Connection from "~handler.remoteAddress()~" closed.");
		} catch (SocketException) {
			logger.warning("Connection closed.");
		}
		handler.close();
		handlers.remove(handler.getSocket);
		logger.info("\tTotal connections: "~to!string(handlers.length));
		commandHandler.lostConnection(handler);
	}
}

class AbstractClientCommandHandler: IClientCommandHandler {
	Server server;
	this(){}
	void handleCommand(IClientHandler socket, string command){};
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
	
	void setup(ref Socket sock, ClientData cd){
		this.socket = sock;
		this.stream = new SocketStream(sock);
		this.clientData = cd;
		this._remoteAddress = remoteAddress();
		this._localAddress = localAddress();
	}
	
	void sendString(string msg){
		stream.writeLine(msg);
	}
	
	void sendBytes(const(ubyte[]) bytes){
		stream.writeLine("+RCV BASE64 "~Base64.encode(bytes));
		string response = to!string(readLine());
		if(response.startsWith("+RCV OK")){
			logger.info("Successfully sent bytes to the client");
		}else if(response.startsWith("+RCV ERR ")){
			string chomped = strip(chompPrefix(response,"+RCV ERR "));
			if(chomped.length > 0){
				logger.error("An error occured on the client while receiving the bytes: "~chomped);
			}else{
				logger.error("An unknown error occured on the client while receiving the bytes");
			}
		}
	}
	
	string readLine(){
		return readString();
	}
	
	string readString(){
		return to!string(stream.readLine());
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
		stream.close();
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
	Socket socket;
	SocketStream stream;
	ClientData clientData;
	string _remoteAddress;
	string _localAddress;
}

interface IClientHandler {
	string 		readString();
	string 		readLine();
	void 		sendString(string msg);
	void  		sendBytes(const(ubyte[]) bytes);
	string 		remoteAddress();
	string 		localAddress();
	void 		setup(ref Socket socket, ClientData cd);
	Socket 		getSocket();
	ClientData 	getClientData();
	void 		close();
}

interface ClientData {}

interface Authenticator { 
	bool 		askAuthorisation(IClientHandler handler); 
	static 		string AUTH_OK = "AUTH OK";
	static 		string AUTH_ERR = "AUTH ERR";
}

abstract class QuickAuthenticator: Authenticator {	
	this(){}
	
	string askStringInput(IClientHandler clientHandler, string prompt){
		clientHandler.sendString(prompt);
		return getStringInput(clientHandler);
	}
	
	string getStringInput(IClientHandler clientHandler){
		return to!string(clientHandler.readLine());
	}
	
	void sendString(IClientHandler clientHandler, string message){
		clientHandler.sendString(message);
	}
}

private:
class AdminAuthenticator: QuickAuthenticator {
	bool askAuthorisation(IClientHandler clientHandler){
		clientHandler.sendString("+OK --------------------------------------");
		clientHandler.sendString("+OK This server requires authentication!");
		clientHandler.sendString("+OK");
		clientHandler.sendString("+OK --------------------------------------");
		
		string username = askStringInput(clientHandler, "+OK Username required");
		string password = askStringInput(clientHandler, "+OK Password required");

        if(username is null || password  is null)
        	return false;

        if(username == password) {
        	sendString(clientHandler, "+OK Logged in");
            return true;
        } else {
            sendString(clientHandler, "-ERR Authorisation Failed");
            return false;
        }
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