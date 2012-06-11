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

int main(char[][] args)
{
	Server server = createSimpleServer();
	server.setCommandHandler("simpleserver.example.SimpleClientCommandHandler");
	server.setAuthenticator("simpleserver.example.DummyAuthenticator");
	server.setSocketHandler("simpleserver.server.DefaultClientHandler");
	server.setClientData("simpleserver.example.MyClientData");
	server.setPort(1234);
	server.setHost("localhost");
	server.setName("SimpleServer EchoService");
	server.startServer();
	server.setAdminPort(2345);
	server.setAdminName("SimpleServer AdminService");
	server.startAdminServer();
	return 0;
}

class MyClientData: ClientData {
	string username;
	ubyte[] bytes;
}

class DummyAuthenticator: QuickAuthenticator {
	bool askAuthorisation(IClientHandler clientHandler){
		string username = askStringInput(clientHandler, "User Name :");
		string password = askStringInput(clientHandler, "Password :");

        if(username is null || password  is null)
        	return false;

        if(username == password) {
        	sendString(clientHandler, AUTH_OK~": Logged in successfully.");
        	MyClientData clientData = cast(MyClientData)clientHandler.getClientData();
	        clientData.username = username;
            return true;
        } else {
            sendString(clientHandler, AUTH_ERR~": Username must equal password.");
            return false;
        }
	}
}

class SimpleClientCommandHandler: AbstractClientCommandHandler {
	this(){
		super();
	}
	
	override void handleCommand(IClientHandler clientHandler, string command){
		MyClientData data = cast(MyClientData)clientHandler.getClientData();
		logger.info("Got message: "~command);
		if(command.startsWith("+RCV BASE64 ")){
			string chomped = strip(chompPrefix(command,"+RCV BASE64 "));
			if(chomped.length==0){
				clientHandler.sendString("+RCV ERR Missing argument?");
			}else{
				clientHandler.sendString("+RCV OK");
				ubyte[] msg = Base64.decode(chomped);
				clientHandler.sendBytes(msg);
				logger.info("Received and echoed "~to!string(msg.length)~" bytes");
				data.bytes = msg;
			}
		}else{
			clientHandler.sendString(command);
			logger.info("Echoed the message");
		}
	}
	
	override void closingConnection(IClientHandler socket){
		logger.info("Closing socket from "~socket.remoteAddress());
	}
	
	override void lostConnection(IClientHandler socket){
		logger.info("Lost connection from "~socket.remoteAddress());
	}
}