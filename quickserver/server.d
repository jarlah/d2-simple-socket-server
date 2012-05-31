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

import std.conv, std.socket, std.stdio, core.thread, std.string, std.ascii;

import quickserver.logger;

class AbstractClientCommandHandler: IClientCommandHandler {
	ILogger logger;
	
	this(){
		logger = getSimpleLogger();
	}
	
	final void handleCommand(ISocketHandler socket, string command){
		handleCommandImpl(socket,command);
	};
	void handleCommandImpl(ISocketHandler socket, string commandHandler){}
	
	final void gotConnected(ISocketHandler socket){
		gotConnectedImpl(socket);
	};
	void gotConnectedImpl(ISocketHandler socket){}
	
	final void gotRejected(Socket socket){
		gotRejectedImpl(socket);
	};
	void gotRejectedImpl(Socket socket){}
	
	final void closingConnection(ISocketHandler socket){
		closingConnectionImpl(socket);
	};
	void closingConnectionImpl(ISocketHandler socket){}
	
	final void lostConnection(ISocketHandler socket){
		lostConnectionImpl(socket);
	};
	void lostConnectionImpl(ISocketHandler socket){}
}

private interface IClientCommandHandler {
	void gotConnected(ISocketHandler handler);
	void gotRejected(Socket socket);
	void closingConnection(ISocketHandler handler);
	void lostConnection(ISocketHandler handler);
	void handleCommand(ISocketHandler handler, string command);
}

public abstract class AbstractSocketHandler: ISocketHandler {
	Socket socket;
	ILogger logger;
	
	this(){}
	
	void setup(Socket sock){
		this.socket = sock;
		this.logger = getSimpleLogger();
	}
	
	void send(string msg){
		int bytesRead = to!int(socket.send(msg~newline));
		if(Socket.ERROR == bytesRead){
			logger.error("An error occured while sending");
		}else{
			logger.info("Sent \""~msg~"\" to client");
		}
	}
	
	int read(ref char[] buf){
		buf = new char[readSize()];
		return to!int(socket.receive(buf));
	}
	
	string remoteAddress(){
		return to!string(socket.remoteAddress().toString());
	}
	
	string localAddress(){
		return to!string(socket.localAddress().toString());
	}
	
	void close(){
		socket.close();
	}
}

public interface ISocketHandler {
	void send(string msg);
	int read(ref char[] buf);
	string remoteAddress();
	string localAddress();
	void close();
	int readSize();
	void setup(Socket socket);
}

public class QuickServer {
	auto MAX 		= 120;
	auto host 		= "localhost";
	auto port 		= 1234;
	auto name 		= "QuickServer";
	auto blocking 	= false;
	auto backlog 	= 60;
	
	IClientCommandHandler commandHandler;
	
	ISocketHandler[Socket] handlers;
	
	ILogger logger;
	
	string handlerClass;
	
	this(string handlerClass){
		commandHandler = cast(IClientCommandHandler) Object.factory(handlerClass);
		enforce(commandHandler);
		logger = getSimpleLogger();
	}
	
	void setSocketHandlerClass(string name){
		handlerClass = name;
	}
	
	void startServer(){
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
					
					char[] buf;
					
					int read = handler.read(buf);

					if (Socket.ERROR == read)
					{
						logger.error("Connection error.");
						goto sock_down;
					}
					else if (0 == read)
					{
						try
						{
							logger.warning("Connection from "~handler.remoteAddress()~" closed.");
						}
						catch (SocketException)
						{
							logger.warning("Connection closed.");
						}

						sock_down:
						handler.close();
						handlers.remove(sock);
						logger.info("\tTotal connections: "~to!string(handlers.length));
						goto next;
					} 
					else
					{
						auto command = buf[0 .. read];
						auto address = handler.remoteAddress();
						logger.info(to!string("Received "~to!string(read)~"bytes  from "~address~": \""~command~"\""));
						commandHandler.handleCommand(handler, to!string(command));
					}
				}
			}
			
			if (sset.isSet(listener))
			{
				Socket sn;
				try
				{
					if (handlers.length < MAX)
					{
						sn = listener.accept();
						assert(sn.isAlive);
						assert(listener.isAlive);
						logger.info("Initializing socket handler");
						ISocketHandler handler = cast(ISocketHandler)Object.factory(handlerClass);
						handler.setup(sn);
						logger.info("Connection from "~handler.remoteAddress~" established.");
						handlers[sn] = handler;
						logger.info("\tTotal connections: "~to!string(handlers.length));
					}
					else
					{
						sn = listener.accept();
						logger.info("Rejected connection from "~to!string(sn.remoteAddress().toString())~"; too many connections.");
						assert(sn.isAlive);
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
}

alias charArr chars;

const(char[]) charArr(string str){
	return cast(const(char[]))str;
}
