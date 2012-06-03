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

import std.conv, std.socket, std.stdio, core.thread, std.concurrency;

import simpleserver.server;

int main(char[][] args)
{
	SimpleServer mainServer =  new SimpleServer();
	
	void executeServer(){
		mainServer.setCommandHandler("echoserver.SimpleClientCommandHandler");
		mainServer.setAuthenticator("echoserver.DummyAuthenticator");
		mainServer.setSocketHandler("simpleserver.server.DefaultClientHandler");
		mainServer.setClientData("echoserver.MyClientData");
		mainServer.setPort(1234);
		mainServer.setHost("localhost");
		mainServer.setName("SimpleServer v1.0");
		mainServer.startServer();
	}
	
	SimpleServer adminServer =  new SimpleServer();
	
	void executeAdminServer(){
		adminServer.setCommandHandler("echoserver.AdminClientCommandHandler");
		adminServer.setAuthenticator("echoserver.AdminAuthenticator");
		adminServer.setSocketHandler("simpleserver.server.DefaultClientHandler");
		adminServer.setClientData("echoserver.MyClientData");
		adminServer.setPort(2345);
		adminServer.setHost("localhost");
		adminServer.setName("SimpleServerAdmin");
		adminServer.disableLog();
		adminServer.startServer(mainServer);
	}
	
	Thread serverThread = new Thread(&executeServer);
	serverThread.start();
	
	Thread adminThread = new Thread(&executeAdminServer);
	adminThread.start();
	
	return 0;
}

class MyClientData: ClientData {
	string username = "unknown";
}

class AdminAuthenticator: QuickAuthenticator {
	bool askAuthorisation(IClientHandler clientHandler){
		clientHandler.send("+OK");
		clientHandler.send("+OK");
		clientHandler.send("+OK");
		clientHandler.send("+OK");
		
		string username = askStringInput(clientHandler, "+OK Username required");
		string password = askStringInput(clientHandler, "+OK Password required");

        if(username is null || password  is null)
        	return false;

        if(username == password) {
        	sendString(clientHandler, "+OK Logged in");
        	MyClientData clientData = cast(MyClientData)clientHandler.getClientData();
	        clientData.username = username;
            return true;
        } else {
            sendString(clientHandler, "-ERR Authorisation Failed");
            return false;
        }
	}
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

class AdminClientCommandHandler: AbstractClientCommandHandler {
	this(){
		super();
	}
	
	override void handleCommand(IClientHandler clientHandler, string command){
		logger.info("Got message: "~command);
		if("version" == command)
			clientHandler.send("+OK "~getServer().getVersionNumber());
		else if("noclient server")
			clientHandler.send("+OK "~to!string(getServer().getNumberOfClients()));
	}
	
	override void closingConnection(IClientHandler socket){
		logger.info("Closing socket from "~socket.remoteAddress());
	}
	
	override void lostConnection(IClientHandler socket){
		logger.info("Lost connection from "~socket.remoteAddress());
	}
}

class SimpleClientCommandHandler: AbstractClientCommandHandler {
	this(){
		super();
	}
	
	override void handleCommand(IClientHandler clientHandler, string command){
		MyClientData clientData = cast(MyClientData)clientHandler.getClientData();
		string username = clientData.username;
		logger.info("Got message: "~command~" from username "~username);
		clientHandler.send(command);
		logger.info("Echoed the message");
	}
	
	override void closingConnection(IClientHandler socket){
		logger.info("Closing socket from "~socket.remoteAddress());
	}
	
	override void lostConnection(IClientHandler socket){
		logger.info("Lost connection from "~socket.remoteAddress());
	}
}