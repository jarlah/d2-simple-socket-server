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

import std.conv, std.socket, std.stdio, core.thread, std.string;

import quickserver.threadpool;

import quickserver.logger;

class AbstractClientCommandHandler: IClientCommandHandler {
	this(){
		logger = getSimpleLogger();
	}
	
	SocketHandler[] sockets;
	
	shared ILogger logger;
	
	ulong _max = 0;
	
	final void handleCommand(SocketHandler socket, string command){
		handleCommandImpl(socket,command);
	};
	void handleCommandImpl(SocketHandler socket, string commandHandler){}
	
	final void gotConnected(SocketHandler socket){
		add(socket);
		gotConnectedImpl(socket);
	};
	void gotConnectedImpl(SocketHandler socket){}
	
	final void gotRejected(Socket socket){
		gotRejectedImpl(socket);
	};
	void gotRejectedImpl(Socket socket){}
	
	final void closingConnection(SocketHandler socket){
		closingConnectionImpl(socket);
	};
	void closingConnectionImpl(SocketHandler socket){}
	
	final void lostConnection(SocketHandler socket){
		del(socket);
		lostConnectionImpl(socket);
	};
	void lostConnectionImpl(SocketHandler socket){}
	
	void broadcast(string msg){
		foreach(SocketHandler socket; sockets){
			socket.send(msg);
		}
	}
	
	final ulong size(){
		return sockets.length;
	}
	
	final void add(SocketHandler socket){
		enforce(socket);
		synchronized
			sockets ~= socket;
		logger.warning("Adding socket to internal list");
	}
	
	final void del(SocketHandler socket){
		synchronized{
			ulong index;
			
			bool found = false;
			
			foreach(int i, SocketHandler sh; sockets){
				if(sh == socket){
					index = i;
					found = true;
					break;
				}
			}
			
			if(found){
				if(sockets.length == 1)
					sockets.clear();
				else
					sockets = sockets[0 .. index] ~ sockets[index + 1 .. sockets.length];
				logger.warning("Deleted socket from internal list: current = "~to!string(size()));
			}	
		}
	}
}

private interface IClientCommandHandler {
	ulong size();
	void add(SocketHandler socket);
	void del(SocketHandler socket);
	void broadcast(string msg);
	void gotConnected(SocketHandler handler);
	void gotRejected(Socket socket);
	void closingConnection(SocketHandler handler);
	void lostConnection(SocketHandler handler);
	void handleCommand(SocketHandler handler, string command);
}

private class SocketHandler{
	private Socket socket;
	private IClientCommandHandler commandHandler;
	private shared ILogger logger;
	private const int bytesToRead = 1024;
	
	public:
	this(Socket sock, IClientCommandHandler commandHandler){
		this.socket = sock;
		this.commandHandler = commandHandler;
		enforce(commandHandler);
		logger = getSimpleLogger();
	}
	
	void send(string msg){
		import std.ascii;
		int bytesRead = to!int(socket.send(msg~newline));
		if(Socket.ERROR == bytesRead){
			logger.error("An error occured while sending");
		}else{
			logger.info("Sent \""~msg~"\" to client");
		}
	}
	
	private:
	void closeConnection(){
		scope(exit)
			commandHandler.lostConnection(this);
		loop = false;
		socket.close();
	}
	
	bool loop = true;
	
	void run(){
		scope(exit){
			closeConnection();
			logger.warning("SocketHandler.run exits");
		}
			
		commandHandler.gotConnected(this);	
		
		while(loop){
			int read;
			char[] buf = receiveFromSocket(bytesToRead, read);
			if (Socket.ERROR == read) {
				logger.warning("Socket.read caught Socket.ERROR");
				break;
			} else if (0 == read) {
				logger.warning("Socket.read caught 0");
				break;
			} else {
				commandHandler.handleCommand(this, strip(to!string(buf[0 .. read])));
			}
		}
	}
	
	char[] receiveFromSocket(uint numBytes, ref int readBytes)
	{
		char[] buf = new char[numBytes];
		readBytes = to!int(socket.receive(buf));
		return buf;
	}
}

public class QuickServer {
	auto host 		= "localhost";
	auto port 		= 1234;
	auto name 		= "QuickServer";
	auto blocking 	= true;
	auto backlog 	= 60;
	const auto max 	= 120;
	
	IClientCommandHandler commandHandler;
	
	ICThreadPool threadPool;	
	
	shared ILogger logger;
	
	this(string handlerClass){
		commandHandler = cast(IClientCommandHandler) Object.factory(handlerClass);
		enforce(commandHandler);
		logger = getSimpleLogger();
	}
	
	void startServer(){
		Socket listener = new TcpSocket;
		assert(listener.isAlive);
		
		listener.blocking = blocking;
		listener.bind(new InternetAddress(chars(host),to!ushort(port)));
		listener.listen(backlog);
			
		logger.info("Listening on port "~to!string(port));
		
		SocketSet sset = new SocketSet();
		sset.add(listener);
		
		// Do not initialize this in the constructor because we want updated values for max and backlog
		threadPool = new CThreadPool(max,600,backlog);
		
		do{
			scope(failure){
				logger.warning("An error occured while accepting. Lets continue.");
				continue;
			}
			
			Socket.select(sset,null,null);
			
			if (commandHandler.size() < max)
			{
				Socket sn = listener.accept();
				
				if(sn is null)
					continue;
					
				assert(sn.isAlive);
				
				void runHandler(){
					auto h = new SocketHandler(sn, commandHandler);
					h.run();
				}
				
				threadPool.append(&runHandler);
			} else {
				logger.warning("Rejected new socket: "~to!string(commandHandler.size()));
			}
		}while(true);
	}
}

alias charArr chars;

const(char[]) charArr(string str){
	return cast(const(char[]))str;
}