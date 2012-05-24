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
module server;

import std.conv, std.socket, std.stdio, core.thread;

alias charArr chars;

const(char[]) charArr(string str){
	return cast(const(char[]))str;
}

int main(char[][] args)
{
	QuickServer server =  new QuickServer("server.SimpleClientCommandHandler");
	server.startServer();
	return 0;
}

class SimpleClientCommandHandler: AbstractClientCommandHandler {
	this(){
		super();
	}
	
	override void handleCommandImpl(SocketHandler socket, string command){
		log("Got message: "~command);
	}
	
	override void closingConnectionImpl(SocketHandler socket){
		log("Closing socket: "~to!string(socket));
	}
}

class AbstractClientCommandHandler: ClientCommandHandler {
	this(){}
	
	uint _size = 0;
	
	SocketHandler[] sockets;
	
	uint size(){ return _size; }
	
	final void handleCommand(SocketHandler socket, string command){
		handleCommandImpl(socket,command);
	};
	
	void handleCommandImpl(SocketHandler socket, string commandHandler){
		// TODO
	}
	
	final void gotConnected(SocketHandler socket){
		increment();
		add(socket);
		gotConnectedImpl(socket);
	};
	
	void gotConnectedImpl(SocketHandler socket){
		// TODO
	}
	
	final void gotRejected(Socket socket){
		gotRejectedImpl(socket);
	};
	
	void gotRejectedImpl(Socket socket){
		// TODO
	}
	
	final void closingConnection(SocketHandler socket){
		closingConnectionImpl(socket);
	};
	
	void closingConnectionImpl(SocketHandler socket){
		// TODO
	}
	
	final void lostConnection(SocketHandler socket){
		decrement();
		del(socket);
		lostConnectionImpl(socket);
	};
	
	void lostConnectionImpl(SocketHandler socket){
		// TODO
	}
	
	final void decrement(){
		synchronized {
			if(_size>0)
				_size--;
			log("Current size is: "~to!string(_size));
		}
	}
	
	final void increment(){
		synchronized {
			_size++;
			log("Current size is: "~to!string(_size));
		}
	}
	
	final void add(SocketHandler socket){
		synchronized {
			enforce(socket);
			sockets ~= socket;
			log("Adding socket to internal list");
		}
	}
	
	final void del(SocketHandler socket){
		synchronized {
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
				log("Found socket");
				if(sockets.length == 1){
					log("Cleared first item from array");
					sockets.clear();
				}else{
					log("Removed item from array");
					sockets = sockets[0 .. index] ~ sockets[index + 1 .. sockets.length];
				}
				log("Deleting socket from internal list");
			}
		}
	}
}

interface ClientCommandHandler {
	void add(SocketHandler socket);
	void del(SocketHandler socket);
	uint size();
	void gotConnected(SocketHandler handler)
	in {
		enforce(handler);
	}

	void gotRejected(Socket socket)
	in {
		enforce(socket);
	}
	
	void closingConnection(SocketHandler handler)
	in {
		enforce(handler);
	}

	void lostConnection(SocketHandler handler)
	in {
		enforce(handler);
	}

	void handleCommand(SocketHandler handler, string command)
	in {
		enforce(handler);
	}
}

class SocketHandler: Thread {
	private Socket socket;

	private ClientCommandHandler commandHandler;
	
	const int bytesToRead = 1024;
	
	this(Socket sock, ClientCommandHandler commandHandler){
		super(&run);
		this.socket = sock;
		this.commandHandler = commandHandler;
		enforce(commandHandler);
	}
	
	private:
	void run(){
		try{
			commandHandler.gotConnected(this);
			while(true){
				int read;
				char[] buf = receiveFromSocket(bytesToRead, read);
				if (Socket.ERROR == read) {
					log("Connection error.");
					goto sock_down;
				} else if (0 == read) {
					sock_down:
					commandHandler.closingConnection(this);
					socket.close();
					break;
				} else {
					commandHandler.handleCommand(this, to!string(buf[0 .. read]));
				}
			}
		}catch(Throwable e){
			log("Socket handler failed");
		}finally{
			commandHandler.lostConnection(this);
		}
	}
	
	char[] receiveFromSocket(uint numBytes, ref int readBytes)
	in {
		enforce(numBytes);
	} out (result) {
		enforce(result);
	} body {
		char[] buf = new char[numBytes];
		readBytes = to!int(socket.receive(buf));
		return buf;
	}
}

class QuickServer {
	auto host 		= "localhost";
	auto port 		= 1234;
	auto name 		= "QuickServer";
	auto blocking 	= true;
	auto backlog 	= 60;
	const auto max 	= 120;
	
	ClientCommandHandler commandHandler;

	this(string handlerClass){
		commandHandler = cast(ClientCommandHandler) Object.factory(handlerClass);
		enforce(commandHandler);
	}
	
	void startServer(){
		Socket listener = new TcpSocket;
		assert(listener.isAlive);
		listener.blocking = blocking;
		listener.bind(new InternetAddress(chars(host),to!ushort(port)));
		listener.listen(backlog);
			
		log("Listening on port "~to!string(port));

		SocketSet sset = new SocketSet();
		sset.add(listener);
		
		do{
			scope(failure){
				log("An error occured while accepting. Lets continue.");
				continue;
			}
			
			Socket.select(sset,null,null);
			
			if (commandHandler.size() < max)
			{
				Socket sn = listener.accept();
				
				if(sn is null)
					continue;
					
				assert(sn.isAlive);
				
				SocketHandler sh = new SocketHandler(sn, commandHandler);
				
				sh.start();
			} else {
				log("Rejected new socket: "~to!string(commandHandler.size()));
			}
		}while(true);
	}
}

void log(string str){
	synchronized{
		writeln(str);
	}
}
