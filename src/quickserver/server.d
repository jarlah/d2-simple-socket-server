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

module quickserver.server;

import std.conv, std.socket, std.socketstream, std.stdio, core.thread, std.string, std.ascii;

import quickserver.logger;

class AbstractClientCommandHandler: IClientCommandHandler {
	ILogger logger;
	this(){ logger = getSimpleLogger(); }
	void handleCommand(ISocketHandler socket, string command){};
	void gotConnected(ISocketHandler socket){};
	void gotRejected(Socket socket){};
	void closingConnection(ISocketHandler socket){};
	void lostConnection(ISocketHandler socket){};
}

private interface IClientCommandHandler {
	void gotConnected(ISocketHandler handler);
	void gotRejected(Socket socket);
	void closingConnection(ISocketHandler handler);
	void lostConnection(ISocketHandler handler);
	void handleCommand(ISocketHandler handler, string command);
}

class DefaultSocketHandler: AbstractSocketHandler {
	this(){}
}

abstract class AbstractSocketHandler: ISocketHandler {
	Socket socket;
	SocketStream stream;
	ClientData clientData;
	ILogger logger;
	
	this(){}
	
	void setup(Socket sock, ClientData clientData){
		this.socket = sock;
		this.stream = new SocketStream(sock);
		this.logger = getSimpleLogger();
		this.clientData = clientData;
	}
	
	void send(string msg){
		stream.writeString(msg~newline);
	}
	
	string readLine(){
		return to!string(stream.readLine());
	}
	
	string remoteAddress(){
		return to!string(socket.remoteAddress().toString());
	}
	
	string localAddress(){
		return to!string(socket.localAddress().toString());
	}
	
	void close(){
		stream.close();
	}
	
	Socket getSocket(){
		return socket;
	}
	
	ClientData getClientData(){
		return clientData;
	}
}

interface ISocketHandler {
	void send(string msg);
	string readLine();
	string remoteAddress();
	string localAddress();
	void setup(Socket socket, ClientData clientData);
	Socket getSocket();
	ClientData getClientData();
	void close();
}

interface ClientData {
	
}

interface Authenticator {
	bool askAuthorisation(ISocketHandler handler);
}

abstract class QuickAuthenticator: Authenticator {	
	string askStringInput(ISocketHandler clientHandler, string prompt){
		if(prompt !is null)
			clientHandler.send(prompt);
		return getStringInput(clientHandler);
	}
	
	string getStringInput(ISocketHandler clientHandler){
		return clientHandler.readLine();
	}
	
	void sendString(ISocketHandler clientHandler, string message){
		clientHandler.send(message);
	}
}

class QuickServer {
	auto MAX 		= 120;
	auto host 		= "localhost";
	auto port 		= 1234;
	auto name 		= "QuickServer";
	auto blocking 	= false;
	auto backlog 	= 60;
	
	IClientCommandHandler commandHandler = null;
	
	ISocketHandler[Socket] handlers;
	
	ILogger logger = null;
	
	Authenticator authHandler = null;
	
	string socketHandlerClass = "quickserver.server.DefaultSocketHandler";
	
	string commandHandlerClass = null;
	
	string authHandlerClass = null;
	
	string clientDataClass = null;
	
	this(){
		logger = getSimpleLogger();
	}
	
	void setCommandHandler(string handlerClass)
	in{
		enforce("Command handler class cannot be null",handlerClass);
	}body{
		
		commandHandlerClass = handlerClass;
	}
	
	void setSocketHandler(string handlerClass)
	in{
		enforce("Socket handler class cannot be null",handlerClass);
	}body{
		socketHandlerClass = handlerClass;
	}
	
	void setAuthenticator(string handlerClass)
	in{
		enforce("Authenticator class cannot be null",handlerClass);
	}body{
		authHandlerClass = handlerClass;
	}
	
	void setClientData(string clientData)
	in{
		enforce("Client data class cannot be null",clientData);
	}body{
		clientDataClass = clientData;
	}
	
	void startServer(){
		logger.info("Starting "~name~"."); 
		
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
		listener.bind(new InternetAddress(chars(host),to!ushort(port)));
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
					
					auto address = handler.remoteAddress();
					logger.info(to!string("Received "~to!string(read.length)~"bytes  from "~address~": \""~read~"\""));
					commandHandler.handleCommand(handler, read);					
				}
			}
			
			if (sset.isSet(listener))
			{
				Socket sn;
				try
				{
					if (handlers.length < MAX)
					{
						scope(failure)
							goto close;
						
						sn = listener.accept();
						assert(sn.isAlive);
						assert(listener.isAlive);
						
						logger.info("Loading socket handler class "~socketHandlerClass);
						ISocketHandler handler = cast(ISocketHandler)Object.factory(socketHandlerClass);
						
						ClientData clientData = null;
						if(clientDataClass !is null){
							logger.info("Loading client data class "~clientDataClass);
							clientData = cast(ClientData)Object.factory(clientDataClass);
						}
						
						handler.setup(sn, clientData);
						
						if(authHandler !is null){
							if(authHandler.askAuthorisation(handler)){
								logger.info("User authenticated");
							}else{
								logger.warning("User failed to authenticate");
								goto close;
							}
						}
						
						logger.info("Connection from "~handler.remoteAddress()~" established.");
						
						handlers[sn] = handler;
						
						logger.info("\tTotal connections: "~to!string(handlers.length));
					}
					else
					{
						sn = listener.accept();
						logger.info("Rejected connection from "~to!string(sn.remoteAddress().toString())~"; too many connections.");
						assert(sn.isAlive);
						close:
						sn.close();
						assert(!sn.isAlive);
						assert(listener.isAlive);
					}
				}
				catch (Exception e)
				{
					logger.error("Error accepting: "~e.toString());
					if (sn)
						sn.close();
				}
			}
		}
	}
	
	void closeSocket(ISocketHandler handler){
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
	}
}

alias charArr chars;

const(char[]) charArr(string str){
	return cast(const(char[]))str;
}
