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

import std.conv, std.socket, std.stdio, core.thread;

import simpleserver.server;

int main(char[][] args)
{
	SimpleServer server =  new SimpleServer();
	server.setCommandHandler("echoserver.SimpleClientCommandHandler");
//	server.setAuthenticator("echoserver.DummyAuthenticator");
	server.setSocketHandler("simpleserver.server.DefaultClientHandler");
	server.setClientData("echoserver.MyClientData");
	server.setPort(1234);
	server.setHost("localhost");
	server.setName("SimpleServer v1.0");
	server.startServer();
	return 0;
}

class MyClientData: ClientData {
	string username = "unknown";
}

class DummyAuthenticator: QuickAuthenticator {
	bool askAuthorisation(IClientHandler clientHandler){
		string username = askStringInput(clientHandler, "User Name :");
		string password = askStringInput(clientHandler, "Password :");

        if(username is null || password  is null)
        	return false;

        if(username == password) {
        	sendString(clientHandler, "Auth OK");
        	MyClientData clientData = cast(MyClientData)clientHandler.getClientData();
	        clientData.username = username;
            return true;
        } else {
            sendString(clientHandler, "Auth Failed");
            return false;
        }
	}
}

class SimpleClientCommandHandler: AbstractClientCommandHandler {
	this(){
		super();
	}
	
	override void handleCommand(IClientHandler clientHandler, string command){
		string username = "unknown";
		MyClientData clientData = cast(MyClientData)clientHandler.getClientData();
		username = clientData.username;
		logger.info("Got message: "~command~" from username "~username);
		clientHandler.send(command);
	}
	
	override void closingConnection(IClientHandler socket){
		logger.info("Closing socket");
	}
	
	override void lostConnection(IClientHandler socket){
		logger.info("Hey I lost my connection");
	}
}