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

import java.io.*;
import java.net.*;
import java.util.concurrent.*;
import java.util.*;

public class SocketClient {
	public static void main (String args[]) throws Exception{
		List<Callable<String>> list = new ArrayList<Callable<String>>();
		int size = 10;
		for(int i = 0;i<size;i++){
			list.add(new Callable<String>(){
				public String call(){
					Socket echoSocket = null;
					PrintWriter out = null;
					BufferedReader in = null;

					try {
						echoSocket = new Socket("localhost", 1234);
						out = new PrintWriter(echoSocket.getOutputStream(), true);
						in = new BufferedReader(new InputStreamReader(echoSocket.getInputStream()));
					} catch (UnknownHostException e) {
						System.err.println("Don't know about host: localhost.");
						System.exit(1);
					} catch (IOException e) {
						System.err.println("Couldn't get I/O for " + "the connection to: localhost.");
						System.exit(1);
					}
									
					out.print("Hei");
					out.flush();
					
					String string = null;
					
					try{
						System.out.println("Trying to read response");
						string = in.readLine();
					}catch(Exception e){
						System.err.println("Could not read response");
					}
					
					try{
						out.close();
						in.close();
						echoSocket.close();
					}catch(Exception e){
						System.err.println("Could not close correctly");
					}
						
					return string;
				}
			});
		}
		
		ExecutorService executor = Executors.newFixedThreadPool(size);
		
		List<Future<String>> result = executor.invokeAll(list);
		
		for(Future<String> r: result){
			String string = r.get();
			System.out.println(string);
		}
		
		System.exit(0);
	}
}
