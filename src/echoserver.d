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

module simpleserver.example;
import std.conv, std.string, std.socket, std.stdio, core.thread, std.concurrency, std.base64;
import simpleserver.server;

void main(char[][] args)
{
	Server server = createSimpleServer();
	
	server.setCommandHandler("simpleserver.example.SimpleClientCommandHandler");
	server.setAuthenticator("simpleserver.example.DummyAuthenticator");
	server.setSocketHandler("simpleserver.server.DefaultClientHandler");
	server.setClientData("simpleserver.example.MyClientData");
	server.setPort(1234);
	server.setHost("localhost");
	server.setName("SimpleServer::Echo");
	
	server.startServer();
	
	server.setAdminPort(2345);
	server.setAdminHost("localhost");
	server.setAdminName("SimpleServer::Admin");
	
	server.startAdminServer();
}

class MyClientData: ClientData {
	string username;
	ubyte[] bytes;
	int count;
}

class DummyAuthenticator: SimpleAuthenticator {
	bool isAuthorized(IClientHandler clientHandler){
		if(username == password){
			clientHandler.sendString("Welcome!");
			return true;
		}else
			return false;
	}
}

class SimpleClientCommandHandler: AbstractClientCommandHandler {
	this(){
		super();
	}
	
	override void handleCommand(IClientHandler clientHandler, string command){
		MyClientData data = cast(MyClientData)clientHandler.getClientData;
		data.count++;
		clientHandler.sendString(command~" for the "~to!string(data.count)~" time");
		logger.info("Echoed the message");
	}
}