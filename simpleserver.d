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

import quickserver.server;

int main(char[][] args)
{
	QuickServer server =  new QuickServer("simpleserver.SimpleClientCommandHandler");
	server.startServer();
	return 0;
}

class SimpleClientCommandHandler: AbstractClientCommandHandler {
	this(){
		super();
	}
	
	override void handleCommandImpl(SocketHandler socket, string command){
		logger.info("Got message: "~command);
		socket.send(command);
	}
	
	override void closingConnectionImpl(SocketHandler socket){
		logger.info("Closing socket");
	}
}