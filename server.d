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
		writeln("initializing simple client handler");
		// TODO
	}
	override void handleCommandImpl(SocketHandler socket, string command){
		writeln("Got message: "~command);
	}
	override void closingConnectionImpl(SocketHandler socket){
		writeln("Closing socket: "~to!string(socket));
	}
}

class AbstractClientCommandHandler: ClientCommandHandler {
	this(){
		writeln("initializing abstract client handler");
		// TODO
	}
	uint _size = 0;
	SocketHandler[] sockets;
	uint size(){ return _size; }
	void handleCommand(SocketHandler socket, string command){
		handleCommandImpl(socket,command);
	};
	void handleCommandImpl(SocketHandler socket, string commandHandler){
		// TODO
	}
	void gotConnected(SocketHandler socket){
		increment();
		add(socket);
		gotConnectedImpl(socket);
	};
	void gotConnectedImpl(SocketHandler socket){
		// TODO
	}
	void gotRejected(Socket socket){
		gotRejectedImpl(socket);
	};
	void gotRejectedImpl(Socket socket){
		// TODO
	}
	void closingConnection(SocketHandler socket){
		closingConnectionImpl(socket);
	};
	void closingConnectionImpl(SocketHandler socket){
		// TODO
	}
	void lostConnection(SocketHandler socket){
		decrement();
		del(socket);
		lostConnectionImpl(socket);
	};
	void lostConnectionImpl(SocketHandler socket){
		// TODO
	}
	void decrement(){
		synchronized {
			_size--;
			writeln("Current size is: "~to!string(_size));
		}
	}
	void increment(){
		synchronized {
			_size++;
			writeln("Current size is: "~to!string(_size));
		}
	}
	void add(SocketHandler socket){
		synchronized {
			enforce(socket);
			sockets ~= socket;
			writeln("Adding socket to internal list. Current size: "~to!string(sockets.length));
		}
	}
	void del(SocketHandler socket){
		synchronized {
			ulong index;
			int i;
			for(i=0;i<sockets.length;i++){
				if(socket == sockets[i]){
					index = i;
					break;
				}
			}
			sockets = sockets[0 .. index] ~ sockets[index + 1 .. sockets.length];
			writeln("Deleting socket from internal list. Current size: "~to!string(sockets.length));
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
	}
	
	private:
	void run(){
		commandHandler.gotConnected(this);
		while(true){
			int read;
			char[] buf = receiveFromSocket(bytesToRead, read);
			if (Socket.ERROR == read) {
				writeln("Connection error.");
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
		commandHandler.lostConnection(this);
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
	auto blocking 	= false;
	auto backlog 	= 10;
	const auto max 	= 60;
	
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
		
		writefln("Listening on port %d.", port);
		
		// I have not passed any size to the SocketSet constructor because I am only going to retain the listener in it.
		SocketSet sset = new SocketSet();
		sset.add(listener);
		
		do{
			writeln("Listening for new socket connections");
			
			Socket.select(sset,null,null);
			
			if(sset.isSet(listener)){
				Socket sn;
				
				scope(failure){
					writefln("Error while trying to accept");
					if (sn)
						sn.close();
				}

				sn = listener.accept();
				
				assert(sn.isAlive);
				
				writeln("Tentatively accepted new socket");
				
				if (commandHandler.size() < max)
				{
					writeln("Acknowledging new socket ...");
					assert(listener.isAlive);
					SocketHandler sh = new SocketHandler(sn, commandHandler);
					sh.start();
					writeln("Acknowledged new socket");
				} else {
					writeln("Rejecting new socket...");
					commandHandler.gotRejected(sn);
					sn.close();
					assert(!sn.isAlive);
					assert(listener.isAlive);
					writeln("Rejected new socket");
				}
			}
		}while(true);
	}
}
