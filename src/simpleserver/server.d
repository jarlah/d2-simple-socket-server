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

import std.conv, std.socket, std.socketstream, std.stdio, core.thread, std.string, std.ascii;

import simpleserver.logger;

class AbstractClientCommandHandler: IClientCommandHandler {
	ILogger logger;
	this(){ logger = getSimpleLogger(); }
	void handleCommand(IClientHandler socket, string command){};
	void gotConnected(IClientHandler socket){};
	void gotRejected(Socket socket){};
	void closingConnection(IClientHandler socket){};
	void lostConnection(IClientHandler socket){};
}

private interface IClientCommandHandler {
	void gotConnected(IClientHandler handler);
	void gotRejected(Socket socket);
	void closingConnection(IClientHandler handler);
	void lostConnection(IClientHandler handler);
	void handleCommand(IClientHandler handler, string command);
}

class DefaultClientHandler: AbstractClientHandler {
	this(){}
}

abstract class AbstractClientHandler: IClientHandler {
	Socket socket;
	SocketStream stream;
	ClientData clientData = null;
	ILogger logger = null;
	string _remoteAddress = null, _localAddress = null;
	
	this(){}
	
	void setup(ref Socket sock, ClientData cd){
		this.socket = sock;
		this.stream = new SocketStream(sock);
		this.logger = getSimpleLogger();
		this.clientData = cd;
		remoteAddress();
		localAddress();
	}
	
	void send(string msg){
		stream.writeLine(msg);
	}
	
	string readLine(){
		return to!string(stream.readLine());
	}
	
	string remoteAddress(){
		if(_remoteAddress is null)
			_remoteAddress = to!string(socket.remoteAddress().toString());
		return _remoteAddress;
	}
	
	string localAddress(){
		if(_localAddress is null)
			_localAddress = to!string(socket.localAddress().toString());
		return _localAddress;
	}
	
	void close(){
		stream.close();
	}
	
	Socket getSocket(){
		return socket;
	}
	
	ClientData getClientData(){
		if(clientData is null)
			throw new Exception("There are no client data on the client handler!");
		return clientData;
	}
}

interface IClientHandler {
	void 	send(string msg);
	string 	readLine();
	string 	remoteAddress();
	string 	localAddress();
	void 	setup(ref Socket socket, ClientData cd);
	Socket 	getSocket();
	ClientData getClientData();
	void 	close();
}

interface ClientData {}

interface Authenticator { bool askAuthorisation(IClientHandler handler); }

abstract class QuickAuthenticator: Authenticator {	
	string askStringInput(IClientHandler clientHandler, string prompt){
		if(prompt !is null)
			clientHandler.send(prompt);
		return getStringInput(clientHandler);
	}
	
	string getStringInput(IClientHandler clientHandler){
		return clientHandler.readLine();
	}
	
	void sendString(IClientHandler clientHandler, string message){
		clientHandler.send(message);
	}
}

class SimpleServer {
	private ILogger logger = null;
	
	public:
	this(){
		logger = getSimpleLogger();
	}
	
	void startServer(){
		logger.info("Starting "~name); 
		
		enforce(commandHandlerClass);
		logger.info("Loading handler class "~commandHandlerClass);
		commandHandler = cast(IClientCommandHandler) Object.factory(commandHandlerClass);
		enforce(commandHandler);
		
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
					
					string read;
					
					scope(failure){
						closeSocket(handler);
						goto next;
					}
					
					read = handler.readLine();
					
					if(read.length==0){
						closeSocket(handler);
						goto next;
					}
					
					logger.info(to!string("Received "~to!string(read.length)~"bytes from "~handler.remoteAddress()~": \""~read~"\""));
					
					commandHandler.handleCommand(handler, read);
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
	
	void setCommandHandler(string handlerClass)
	in{
		enforce("Command handler class cannot be null",handlerClass);
	}body{
		this.commandHandlerClass = handlerClass;
	}
	
	void setSocketHandler(string handlerClass)
	in{
		enforce("Socket handler class cannot be null",handlerClass);
	}body{
		this.socketHandlerClass = handlerClass;
	}
	
	void setAuthenticator(string handlerClass)
	in{
		enforce("Authenticator class cannot be null",handlerClass);
	}body{
		this.authHandlerClass = handlerClass;
	}
	
	void setName(string name)
	in{
		enforce("Name cannot be null",name);
	}body{
		this.name = name;
	}
	
	void setClientData(string clientData)
	in{
		enforce("Client data class cannot be null",clientData);
	}body{
		this.clientDataClass = clientData;
	}
	
	void setPort(int port)
	in{
		assert(port>0,"Port > 0");
	}body{
		this.port = port;
	}
	
	void setHost(string host)
	in{
		enforce("Host cannot be null",host);
	}body{
		this.host = host;
	}
	
	void setMax(int max)
	in{
		assert(max>1, "Max be larger than 0");
	}body{
		this.MAX = max;
	}
	
	void setBacklog(int bl)
	in{
		assert(bl>1, "Backlog be larger than 0");
	}body{
		this.backlog = bl;
	}
	
	void setBlocking(bool boolean)
	{
		this.blocking = boolean;
	}
	
	void setSocketTimeout(std.socket.Duration dur){
		this.socketTimeout = dur;
	}
	
	private:
	int MAX = 120;
	string host = "localhost";
	int port = 1234;
	string name = "SimpleServer";
	bool blocking = false;
	int backlog = 60;
	std.socket.Duration socketTimeout = dur!"seconds"(60);
	string socketHandlerClass = "simpleserver.server.DefaultClientHandler";
	string commandHandlerClass = null;
	string authHandlerClass = null;
	string clientDataClass = null;
	IClientCommandHandler commandHandler = null;
	IClientHandler[Socket] handlers;
	Authenticator authHandler = null;
	
	void closeSocket(IClientHandler handler){
		commandHandler.closingConnection(handler);
		
		try
		{
			logger.warning("Connection from "~handler.remoteAddress()~" closed.");
		}
		catch (SocketException)
		{
			logger.warning("Connection closed.");
		}
		
		handler.close();
		
		handlers.remove(handler.getSocket);
		
		logger.info("\tTotal connections: "~to!string(handlers.length));
		
		commandHandler.lostConnection(handler);
	}
}