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
		socket.send("Hello! You typed: "~command);
		broadcast("Someone typed: "~command);
	}
	
	override void closingConnectionImpl(SocketHandler socket){
		log("Closing socket: "~to!string(socket));
	}
}

class AbstractClientCommandHandler: IClientCommandHandler {
	this(){}
	
	SocketHandler[] sockets;
	
	ulong _max = 0;
	
	final void handleCommand(SocketHandler socket, string command){
		handleCommandImpl(socket,command);
	};
	void handleCommandImpl(SocketHandler socket, string commandHandler){}
	
	final void gotConnected(SocketHandler socket){
		add(socket);
		gotConnectedImpl(socket);
	};
	void gotConnectedImpl(SocketHandler socket){}
	
	final void gotRejected(Socket socket){
		gotRejectedImpl(socket);
	};
	void gotRejectedImpl(Socket socket){}
	
	final void closingConnection(SocketHandler socket){
		closingConnectionImpl(socket);
	};
	void closingConnectionImpl(SocketHandler socket){}
	
	final void lostConnection(SocketHandler socket){
		del(socket);
		lostConnectionImpl(socket);
	};
	void lostConnectionImpl(SocketHandler socket){}
	
	void broadcast(string msg){
		synchronized(this){
			foreach(SocketHandler socket; sockets){
				socket.send(msg);
			}
		}
	}
	
	final ulong size(){
		synchronized(this){
			return sockets.length;
		}
	}
	
	final void add(SocketHandler socket){
		synchronized(this) {
			enforce(socket);
			sockets ~= socket;
			log("Adding socket to internal list");
		}
	}
	
	final void del(SocketHandler socket){
		synchronized(this) {
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
				if(sockets.length == 1){
					sockets.clear();
				}else{
					sockets = sockets[0 .. index] ~ sockets[index + 1 .. sockets.length];
				}
				log("Deleted socket from internal list: current = "~to!string(size()));
			}
		}
	}
}

interface IClientCommandHandler {
	ulong size();
	void add(SocketHandler socket);
	void del(SocketHandler socket);
	void broadcast(string msg);
	void gotConnected(SocketHandler handler);
	void gotRejected(Socket socket);
	void closingConnection(SocketHandler handler);
	void lostConnection(SocketHandler handler);
	void handleCommand(SocketHandler handler, string command);
}

class SocketHandler{
	private Socket socket;

	private IClientCommandHandler commandHandler;
	
	const int bytesToRead = 1024;
	
	public:
	this(Socket sock, IClientCommandHandler commandHandler){
		this.socket = sock;
		this.commandHandler = commandHandler;
		enforce(commandHandler);
	}
	
	void send(string msg){
		socket.send(msg);
	}
	
	private:
	void run(){
		scope(exit)
			commandHandler.lostConnection(this);
			
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
	}
	
	char[] receiveFromSocket(uint numBytes, ref int readBytes)
	{
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
	
	IClientCommandHandler commandHandler;

	this(string handlerClass){
		commandHandler = cast(IClientCommandHandler) Object.factory(handlerClass);
		enforce(commandHandler);
	}
	
	void startServer(){
		Socket listener = new TcpSocket;
		assert(listener.isAlive);
		listener.blocking = blocking;
		listener.bind(new InternetAddress(chars(host),to!ushort(port)));
		listener.listen(backlog);
			
		log("Listening on port "~to!string(port));

		CThreadPool pool = new CThreadPool(max,600,backlog);
		
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
				
				void runHandler(){
					auto h = new SocketHandler(sn, commandHandler);
					h.run();
				}
				
				pool.append(&runHandler);
			} else {
				log("Rejected new socket: "~to!string(commandHandler.size()));
			}
		}while(true);
	}
}

alias charArr chars;

const(char[]) charArr(string str){
	return cast(const(char[]))str;
}

alias logToStdout log;

void logToStdout(string str){
	synchronized{
		writeln(str);
	}
}

import core.sys.posix.pthread;  // just for pthread_self()
import core.thread;
import core.sync.mutex;
import core.sync.condition;
import std.c.time;

private struct Job
{
       Job *next;
       void function() fn;
       void delegate() dg;
       void *arg;
       int   call;
}

/**
 * Created and posted on D Lang forum by nickname "zsxxsz".
 * 
* semi-daemon thread of thread pool
*/
class CThreadPool
{
public:
       /**
        * Constructs a CThreadPool
        * @param nMaxThread {int} the max number threads in thread pool
        * @param idleTimeout {int} when > 0, the idle thread will
        *  exit after idleTimeout seconds, if == 0, the idle thread
        *  will not exit
        * @param sz {size_t} when > 0, the thread will be created which
        *  stack size is sz.
        */
       this(int nMaxThread, int idleTimeout, size_t sz = 0)
       {
               m_nMaxThread = nMaxThread;
               m_idleTimeout = idleTimeout;
               m_stackSize = sz;
               m_mutex = new Mutex;
               m_cond = new Condition(m_mutex);
       }

       /**
        * Append one task into the thread pool's task queue
        * @param fn {void function()}
        */
       void append(void function() fn)
       {
               Job *job;
               char  buf[256];

               if (fn == null)
                       throw new Exception("fn null");

               job = new Job;
               job.fn = fn;
               job.next = null;
               job.call = Call.FN;

               m_mutex.lock();
               append(job);
               m_mutex.unlock();
       }

       /**
        * Append one task into the thread pool's task queue
        * @param dg {void delegate()}
        */
       void append(void delegate() dg)
       {
               Job *job;
               char  buf[256];

               if (dg == null)
                       throw new Exception("dg null");

               job = new Job;
               job.dg = dg;
               job.next = null;
               job.call = Call.DG;

               m_mutex.lock();
               append(job);
               m_mutex.unlock();
       }

       /**
        * If dg not null, when one new thread is created, dg will be called.
        * @param dg {void delegate()}
        */
       void onThreadInit(void delegate() dg)
       {
               m_onThreadInit = dg;
       }

       /**
        * If dg not null, before one thread exits, db will be called.
        * @param dg {void delegate()}
        */
       void onThreadExit(void delegate() dg)
       {
               m_onThreadExit = dg;
       }

private:
       enum Call { NO, FN, DG }

       Mutex m_mutex;
       Condition m_cond;
       size_t m_stackSize = 0;

       Job* m_jobHead = null, m_jobTail = null;
       int m_nJob = 0;
       bool m_isQuit = false;
       int m_nThread = 0;
       int m_nMaxThread;
       int m_nIdleThread = 0;
       int m_overloadTimeWait = 0;
       int m_idleTimeout;
       time_t m_lastWarn;

       void delegate() m_onThreadInit;
       void delegate() m_onThreadExit;
       void append(Job *job)
       {
               if (m_jobHead == null)
                       m_jobHead = job;
               else
                       m_jobTail.next = job;
               m_jobTail = job;

               m_nJob++;

               if (m_nIdleThread > 0) {
                       m_cond.notify();
               } else if (m_nThread < m_nMaxThread) {
                       Thread thread = new Thread(&doJob);
                       thread.isDaemon = true;
                       thread.start();
                       m_nThread++;
               } else if (m_nJob > 10 * m_nMaxThread) {
                       time_t now = time(null);
                       if (now - m_lastWarn >= 2) {
                               m_lastWarn = now;
                       }
                       if (m_overloadTimeWait > 0) {
                               Thread.sleep(m_overloadTimeWait);
                       }
               }
       }
       void doJob()
       {
               Job *job;
               int status;
               bool timedout;
               long period = m_idleTimeout * 10_000_000;

               if (m_onThreadInit != null)
                       m_onThreadInit();

               m_mutex.lock();
               for (;;) {
                       timedout = false;

                       while (m_jobHead == null && !m_isQuit) {
                               m_nIdleThread++;
                               if (period > 0) {
                                       try {
                                               if (m_cond.wait(period) ==
false) {
                                                       timedout = true;
                                                       break;
                                               }
                                       } catch (SyncException e) {
                                               m_nIdleThread--;
                                               m_nThread--;
                                               m_mutex.unlock();
                                               if (m_onThreadExit != null)
                                                       m_onThreadExit();
                                               throw e;
                                       }
                               } else {
                                       m_cond.wait();
                               }
                               m_nIdleThread--;
                       }  /* end while */
                       job = m_jobHead;

                       if (job != null) {
                               m_jobHead = job.next;
                               m_nJob--;
                               if (m_jobTail == job)
                                       m_jobTail = null;
                               /* the lock shuld be unlocked before enter
working processs */
                               m_mutex.unlock();
                               switch (job.call) {
                               case Call.FN:
                                       job.fn();
                                       break;
                               case Call.DG:
                                       job.dg();
                                       break;
                               default:
                                       break;
                               }

                               /* lock again */
                               m_mutex.lock();
                       }
                       if (m_jobHead == null && m_isQuit) {
                               m_nThread--;
                               if (m_nThread == 0)
                                       m_cond.notifyAll();
                               break;
                       }
                       if (m_jobHead == null && timedout) {
                               m_nThread--;
                               break;
                       }
               }

               m_mutex.unlock();

               writefln("Thread(%d) of ThreadPool exit now", pthread_self());
               if (m_onThreadExit != null)
                       m_onThreadExit();
       }
}

import std.stdio;
unittest
{
       CThreadPool pool = new CThreadPool(10, 10);

       void testThreadInit(string s)
       {
               void onThreadInit()
               {
                       writefln("thread(%d) was created now, s: %s",
pthread_self(), s);
               }
               pool.onThreadInit(&onThreadInit);
       }

       void testThreadExit(string s)
       {
               void onThreadExit()
               {
                       writefln("thread(%d) was to exit now, s: %s",
pthread_self(), s);
               }
               pool.onThreadExit(&onThreadExit);
       }

       void testAddJobs(string s)
       {
               void threadFun()
               {
                       writef("doJob thread id: %d, str: %s\n",
pthread_self(), s);
                       Thread.sleep(10_000_000);
                       writef("doJob thread id: %d, wakeup now\n",
pthread_self());
               }
               pool.append(&threadFun);
               pool.append(&threadFun);
               pool.append(&threadFun);
       }

       string s = "hello world";
       string s1 = "new thread was ok now";
       string s2 = "thread exited now";
       testThreadInit(s1);
       testThreadExit(s2);

       testAddJobs(s);

       Thread.sleep(100_000_000);
}
