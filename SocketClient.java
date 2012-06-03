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

/**
 * Yes it is profoundly ugly.
 * 
 * But it works.
 * 
 * Verifies that the SimpleServer requests and responds properly.
 * 
 * @author Jarl André Hübenthal
 */
public class SocketClient {
	public static void main (String args[]) throws Exception{
		List<Callable<String>> list = new ArrayList<Callable<String>>();
		int size = 100;
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
						
					try {			
						String prompt = in.readLine();
						out.print("jarl\n");
						out.flush();
						prompt = in.readLine();
						out.print("jarl\n");
						out.flush();
					}catch(Exception e){
						System.err.println(e.getLocalizedMessage());
					}
					
					String string = null;

					try {			
						String prompt = in.readLine();
						if(prompt.contains("Auth OK")){
							out.print("Dette er en test\n");
							out.flush();
							Thread.sleep(2000);
						 }
					}catch(Exception e){
						System.err.println(e.getLocalizedMessage());
					}
					
					
					try{
						String result = null;
						while(in.ready() && (result = in.readLine())!=null){
							string = result;
						}
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
		
		int ok = 0;
		
		for(Future<String> r: result){
			String string = r.get();
			if(string == null)
				System.err.println("Got empty response");
			else if(!string.contains("Dette er en test")){
				System.err.println("Does not match; "+string);
			}else{
				ok++;
			}
		}
		
		System.out.println(ok+" out of "+size+" successful");
		
		System.exit(0);
	}
}
