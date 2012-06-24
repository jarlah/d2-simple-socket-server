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
	
	public static String sendAndWait(String msg, BufferedReader in, PrintWriter out) throws Exception{
		out.print(msg+"\n");
		out.flush();
		return in.readLine();
	}
	
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
					
					String string = null;
						
					try {			
						String prompt = in.readLine();
						if(prompt!=null && prompt.contains(":AUTH NICK")){
							prompt = sendAndWait("jarl",in, out);
							if(prompt!=null && prompt.contains(":AUTH PASS")){
								prompt = sendAndWait("jarl",in, out);
								if(prompt.contains("Welcome!")){
									prompt = sendAndWait("Dette er en test",in, out);
								}
							}
						}else{
							prompt = sendAndWait("Dette er en test",in, out);
						 }
						 string = prompt;
					}catch(Exception e){
						System.err.println(e.getLocalizedMessage());
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
			else if(!string.startsWith("Dette er en test")){
				System.err.println("Does not match; "+string);
			}else{
				ok++;
			}
		}
		
		System.out.println(ok+" out of "+size+" successful");
		
		System.exit(0);
	}
}
