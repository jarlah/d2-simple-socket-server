/*
	Copyright (C) 2006-2007 Christopher E. Miller
	
	This software is provided 'as-is', without any express or implied
	warranty.  In no event will the authors be held liable for any damages
	arising from the use of this software.
	
	Permission is granted to anyone to use this software for any purpose,
	including commercial applications, and to alter it and redistribute it
	freely, subject to the following restrictions:
	
	1. The origin of this software must not be misrepresented; you must not
	   claim that you wrote the original software. If you use this software
	   in a product, an acknowledgment in the product documentation would be
	   appreciated but is not required.
	2. Altered source versions must be plainly marked as such, and must not be
	   misrepresented as being the original software.
	3. This notice may not be removed or altered from any source distribution.
*/

/*
	The source has been altered from the original version as stated above.
*/

/** $(B ) Splat: the socket platform with the lame name. It's full of puns, but it runs!
	<a href="http://www.dprogramming.com/splat.php">Download Splat</a>.
	Version 0.7.
	For both Phobos and Tango; tested with Phobos and Tango 0.99.2.
**/
module simpleserver.splat;


private
{
	version(Windows)
	{
		import std.c.windows.windows;
	}
	
	alias long spdTime;
	alias std.datetime.Clock.currStdTime stdCurrentTime;
	import std.socket;
	alias std.socket.InternetHost spdInternetHost;
	alias std.socket.InternetAddress spdInternetAddress;
	alias std.socket.timeval spdMyTimeval;
	alias std.socket.timeval spdTimeval;
	import core.thread;
	import std.conv;
	import std.c.stdio;
}

/**
	Run the event loop; wait for timer and socket events.
	Exceptions that occur in event callbacks break out of run.
**/
void run()
{
	_texit = false;
	
	Timer tn;
	
	spdMyTimeval* ptv;
	spdMyTimeval tv;
	spdTime dnow;

	SocketSet reads = new SocketSet();
	SocketSet writes = new SocketSet();

	int i;

	bool dotimer = false;
	
	for(;;)
	{
		tn = _tnext();
		
		version(Windows)
		{
			if(!_tallEvents.length)
			{
				no_socket_events:
				DWORD ms = INFINITE;
				if(tn)
				{
					dnow = stdCurrentTime();
					if(tn._talarm <= dnow)
						goto timedout;
					ms = _tticksToMs(cast(spdTime)(tn._talarm - dnow));
					
				}
				
				if(INFINITE == ms)
				{
					if(_areHosts()){
						ms = 200;
					}
				}
				
				debug(splat)
				{
					if(INFINITE != ms)
						printf("  {SLEEP} %lu ms\n", cast(uint)ms);
					else
						printf("  {SLEEP} infinite\n");
				}
				
				Sleep(ms);
				goto timedout;
			}
		}
		
		ptv = null;
		if(tn)
		{
			debug(splat)
				printf("splattimer: diff = %d; dotimer = %s\n",
						cast(int)(dnow - tn._talarm),
						dotimer ? "true".ptr : "false".ptr);
			
			if(tn._talarm <= dnow)
			{
				version(Windows)
				{
					assert(_tallEvents.length);
				}
				else
				{
					if(!_tallEvents.length)
						goto timedout;
				}
				if(dotimer)
					goto timedout;
				dotimer = true; // Do timer next time around.
				tv.seconds = 0;
				tv.microseconds = 0;
			}
			else
			{
				dnow = stdCurrentTime();
				_tticksToTimeval(tn._talarm - dnow, &tv);
				if(tv.microseconds < 0)
					tv.microseconds = 0;
				if(tv.seconds < 0)
					tv.seconds = 0;
				if(tv.seconds > 60)
					tv.seconds = 60;
				
				if(_areHosts())
				{
					if(tv.seconds || tv.microseconds > 200_000)
					{
						tv.seconds = 0;
						tv.microseconds = 200_000;
					}
				}
			}
			ptv = &tv;
		}
		else
		{
			debug(splattimer)
				printf("splattimer: no timers\n");
			
			if(_areHosts())
			{
				tv.seconds = 0;
				tv.microseconds = 200_000;
				ptv = &tv;
			}
		}
		
		reads.reset();
		writes.reset();
		
		uint numadds = 0;
		foreach(socket_t key; _tallEvents.keys)
		{
			AsyncSocket sock = _tallEvents[key];
			
			//debug
			debug(splat)
			{
				if(!sock.isAlive())
				{
					deadSocket(key);
					continue;
				}
			}
			
			if(((sock._events & EventType.READ) && !(sock._events & EventType._CANNOT_READ))
				|| ((sock._events & EventType.ACCEPT) && !(sock._events & EventType._CANNOT_ACCEPT))
				|| ((sock._events & EventType.CLOSE) && !(sock._events & EventType._CANNOT_CLOSE)))
			{
				reads.add(sock);
				numadds++;
			}
			
			if(((sock._events & EventType.WRITE) && !(sock._events & EventType._CANNOT_WRITE))
				|| ((sock._events & EventType.CONNECT) && !(sock._events & EventType._CANNOT_CONNECT)))
			{
				writes.add(sock);
				numadds++;
			}
		}
		
		if(_texit)
			return;
		
		version(Windows)
		{
			if(!numadds)
				goto no_socket_events;
		}
		
		debug(splat)
		{
			if(ptv)
			{
				if(0 != ptv.seconds || 0 != ptv.microseconds)
					printf("  {SELECT} %lu secs, %lu microsecs\n", cast(uint)ptv.seconds, cast(uint)ptv.microseconds);
			}
		}
		
		debug(splatselect)
			printf("Socket.select(%u sockets%s)\n", numadds,
				ptv ? (((0 != ptv.seconds || 0 != ptv.microseconds)) ? ", timeout".ptr : ", 0 timeout") : ", infinite-wait".ptr);

		i = Socket.select(reads, writes, null, cast(spdTimeval*)ptv);

		switch(i)
		{
			case -1: // Interruption.
				continue; // ?
			
			case 0: // Timeout.
				goto timedout;
			
			default: // Socket event(s).
				foreach(socket_t key; _tallEvents.keys)
				{
					AsyncSocket sock = _tallEvents[key];
					
					if(_texit)
						return;
					
					if(!sock.isAlive()){
						deadSocket(key);
						continue;
					}
					
					if(reads.isSet(sock))
					{
						if((sock._events & EventType.READ) && !(sock._events & EventType._CANNOT_READ))
						{
							switch(sock._peekreceiveclose())
							{
								case 0: // Close.
									if((sock._events & EventType.CLOSE) && !(sock._events & EventType._CANNOT_CLOSE))
									{
										goto got_close;
									}
									else
									{
										sock._events |= EventType._CANNOT_CLOSE | EventType._CANNOT_READ; // ?
									}
									break;
								case -1: // Error.
									if((sock._events & EventType.CLOSE) && !(sock._events & EventType._CANNOT_CLOSE))
									{
										sock._events |= EventType._CANNOT_CLOSE | EventType._CANNOT_READ; // ?
										sock._tgotEvent(EventType.CLOSE, -1); // ?
									}
									else
									{
										sock._events |= EventType._CANNOT_CLOSE | EventType._CANNOT_READ; // ?
										sock._tgotEvent(EventType.READ, -1);
									}
									break;
								default: // Good.
									sock._events |= EventType._CANNOT_READ;
									sock._tgotEvent(EventType.READ, 0);
							}
						}
						else if((sock._events & EventType.CLOSE) && !(sock._events & EventType._CANNOT_CLOSE))
						{
							switch(sock._peekreceiveclose())
							{
								case 0: // Close.
									got_close:
									sock._events |= EventType._CANNOT_CLOSE | EventType._CANNOT_READ; // ?
									sock._tgotEvent(EventType.CLOSE, 0);
									break;
								case -1: // Error.
									sock._events |= EventType._CANNOT_CLOSE | EventType._CANNOT_READ; // ?
									sock._tgotEvent(EventType.CLOSE, -1);
									break;
								default: ;
							}
						}
						
						
						if((sock._events & EventType.ACCEPT) && !(sock._events & EventType._CANNOT_ACCEPT))
						{
							sock._events |= EventType._CANNOT_ACCEPT;
							sock._tgotEvent(EventType.ACCEPT, 0);
						}
						
						continue; // Checking for writability (otherwise next) on a closed socket (from any above event) is problematic.
					}
					
					if(_texit)
						return;
					
					if(writes.isSet(sock))
					{
						if((sock._events & EventType.CONNECT) && !(sock._events & EventType._CANNOT_CONNECT))
						{
							sock._events |= EventType._CANNOT_CONNECT;
							sock._tgotEvent(EventType.CONNECT, 0);
						}
						
						if((sock._events & EventType.WRITE) && !(sock._events & EventType._CANNOT_WRITE))
						{
							sock._events |= EventType._CANNOT_WRITE;
							sock._tgotEvent(EventType.WRITE, 0);
						}
					}
				}
				//continue;
				goto do_hosts;
		}
		
		// Check timers..
		timedout: ;
		dotimer = false;
		_tdotimers();
		
		// Check resolved hosts..
		do_hosts:
		GetHost gh;
		while(null !is (gh = _tnextDoneHost()))
		{
			gh._tgotEvent();
			
			if(_texit)
				return;
		}
		
		if(_texit)
			return;
	}
}

void deadSocket(socket_t key) {
	debug(splat)
	{
		printf("Splat warning: dead socket still waiting for events\n");
		fflush(stdout);
	}
	
	_tallEvents.remove(key);
}

/// Causes run() to return as soon as it can.
void exitLoop()
{
	_texit = true;
}

private void _tdotimers()
{
	size_t nalarms;
	Timer[4] talarms;
	spdTime dnow;
	Timer tn;
	dnow = stdCurrentTime();
	for(tn = _tfirst; tn; tn = tn._tnext)
	{
		if(dnow >= tn._talarm)
		{
			if(nalarms < talarms.length)
				talarms[nalarms] = tn;
			nalarms++;
		}
	}
	Timer[] nowalarm;
	if(nalarms <= talarms.length)
	{
		nowalarm = talarms[0 .. nalarms];
	}
	else
	{
		nowalarm = new Timer[nalarms];
		nalarms = 0;
		for(tn = _tfirst; tn; tn = tn._tnext)
		{
			if(dnow >= tn._talarm)
			{
				nowalarm[nalarms] = tn;
				nalarms++;
			}
		}
		assert(nowalarm.length == nalarms);
	}
	
	foreach(Timer t; nowalarm)
	{
		if(_texit)
			return;
		
		if(t._talarm != t._TALARM_INIT) // Make sure not removed by some other timer event.
		{
			t._talarm = cast(spdTime)(dnow + t._ttimeout); // Also update alarm time BEFORE in case of exception (could cause rapid fire otherwise).
			t._tgotAlarm();
			if(t._talarm != t._TALARM_INIT) // Maybe removed itself.
			{
				// Set new alarm after this alarm due to possible delay AND possible updated timeout/interval.
				dnow = stdCurrentTime(); // In case time lapses in some other timer event.
				t._talarm = cast(spdTime)(dnow + t._ttimeout);
			}
		}
	}
}


/// Timers; alarms (timeout events) depend on run().
class Timer
{
	/// Property: get and set the timer _interval in milliseconds.
	final void interval(uint iv) // setter
	{
		iv = cast(uint)_tmsToTicks(iv);
		if(!iv)
			iv = 1;
		if(iv != _ttimeout)
		{
			_ttimeout = iv;
			
			if(_talarm != _TALARM_INIT)
			{
				stop();
				start();
			}
		}
	}
	
	/// ditto
	final uint interval() // getter
	{
		return _tticksToMs(cast(spdTime)_ttimeout);
	}
	
	
	/// Start this timer.
	final void start()
	{
		if(_talarm)
			return;
		
		assert(_ttimeout > 0);
		
		_tadd(this);
		
//		debug(splat)
//		{
			printf("  {ADDTIMER:%p} %lu ms\n", cast(void*)this, interval);
//		}
	}
	
	
	/// Stop this timer.
	final void stop()
	{
		if(_talarm)
		{
			_tremove(this);
			
//			debug(splat)
//			{
				printf("  {DELTIMER:%p} %lu ms\n", cast(void*)this, interval);
//			}
		}
	}
	
	
	/// Override to be notified when the time expires. Alarms continue until stop().
	void onAlarm()
	{
		if(_tick)
			_tick(this);
	}
	
	
	/// Construct a timer; can take a delegate that is called back automatically on an alarm.
	this()
	{
		_ttimeout = cast(uint)_tmsToTicks(100);
	}
	
	/// ditto
	this(void delegate(Timer) dg)
	{
		this();
		this._tick = dg;
	}
	
	
	private:
	const spdTime _TALARM_INIT = cast(spdTime)0;
	spdTime _talarm = _TALARM_INIT; // Time when next event is alarmed.
	uint _ttimeout; // Ticks per timeout.
	Timer _tprev, _tnext;
	void delegate(Timer) _tick;
	
	
	void _tgotAlarm()
	{
//		debug(splat)
//		{
			printf("  {TIMER:%p}\n", cast(void*)this);
//		}
		
		onAlarm();
	}
}


// Can be OR'ed.
/// Socket event flags.
enum EventType
{
	NONE = 0, ///
	
	READ =       0x1, ///
	WRITE =      0x2, /// ditto
	//OOB =        0x4, /// ditto
	ACCEPT =     0x8, /// ditto
	CONNECT =    0x10, /// ditto
	CLOSE =      0x20, /// ditto
	
	_CANNOT_READ = READ << 16, // package
	_CANNOT_WRITE = WRITE << 16, // package
	//_CANNOT_OOB = OOB << 16, // package
	_CANNOT_ACCEPT = ACCEPT << 16, // package
	_CANNOT_CONNECT = CONNECT << 16, // package
	_CANNOT_CLOSE = CLOSE << 16, // package
}

private EventType _tEventType_ALL = EventType.READ | EventType.WRITE /+ | EventType.OOB +/
	| EventType.ACCEPT | EventType.CONNECT | EventType.CLOSE;
private EventType _tEventType_ALLREADS = EventType.READ | EventType.ACCEPT | EventType.CLOSE;
private EventType _tEventType_ALLWRITES = EventType.WRITE | EventType.CONNECT;


/**
	Callback type for socket events.
	Params:
		sock = the socket
		type = which event; will be only one of the event flags.
		err = an error code, or 0 if successful.
**/
alias void delegate(Socket sock, EventType type, int err) RegisterEventCallback;


/// Asynchronous sockets; socket events depend on run(). Mostly the same as std.socket.Socket.
class AsyncSocket: Socket
{
	this(AddressFamily af, SocketType type, ProtocolType protocol)
	{
		super(af, type, protocol);
		super.blocking = false;
	}
	
	
	this(AddressFamily af, SocketType type)
	{
		super(af, type);
		super.blocking = false;
	}
	
	
	this(AddressFamily af, SocketType type, char[] protocolName)
	{
		super(af, type, protocolName);
		super.blocking = false;
	}
	
	/**
		Registers a callback for specified socket events.
		One or more type flags may be used, or NONE to cancel all.
		Calling this twice on the same socket cancels out previously registered events for the socket.
	**/
	// Requires run() loop.
	void event(EventType events, RegisterEventCallback callback)
	{
		this.blocking = false;
		
		this._events = EventType.NONE;
		
		if(!(events & (_tEventType_ALLREADS | _tEventType_ALLWRITES)))
			return;
		
		if(isAlive()) // Alive socket already connected or never will.
			this._events |= EventType._CANNOT_CONNECT;
		
		if(events & EventType.ACCEPT)
			events &= ~(EventType.READ | EventType.CLOSE); // Issues in select() if accept and these set.
		
		this._events = events | _tEventType_ALL;
		this._callback = callback;
		
		_tallEvents[this.handle] = this;
	}
	
	// For use with accepting().
	protected this(){}
	
	protected override AsyncSocket accepting()
	{
		return new AsyncSocket();
	}
	
	override void close()
	{
		_events = EventType.NONE;
		_tallEvents.remove(this.handle);
		super.close();
	}
	
	
	override bool blocking() // getter
	{
		return false;
	}
	
	
	override void blocking(bool byes) // setter
	{
		if(byes)
			assert(0);
	}
	
	override long receive(void[] buf, SocketFlags flags)
	{
		_events &= ~EventType._CANNOT_READ;
		return super.receive(buf, flags);
	}
	
	override long receive(void[] buf)
	{
		_events &= ~EventType._CANNOT_READ;
		return super.receive(buf);
	}
	
	override long receiveFrom(void[] buf, SocketFlags flags, ref Address from)
	{
		_events &= ~EventType._CANNOT_READ;
		return super.receiveFrom(buf, flags, from);
	}
	
	override long receiveFrom(void[] buf, ref Address from)
	{
		_events &= ~EventType._CANNOT_READ;
		return super.receiveFrom(buf, from);
	}
	
	override long receiveFrom(void[] buf, SocketFlags flags)
	{
		_events &= ~EventType._CANNOT_READ;
		return super.receiveFrom(buf, flags);
	}
	
	override long receiveFrom(void[] buf)
	{
		_events &= ~EventType._CANNOT_READ;
		return super.receiveFrom(buf);
	}
	
	override long send(const(void)[] buf, SocketFlags flags)
	{
		_events &= ~EventType._CANNOT_WRITE;
		return super.send(buf, flags);
	}
	
	override long send(const(void)[] buf)
	{
		_events &= ~EventType._CANNOT_WRITE;
		return super.send(buf);
	}
	
	override long sendTo(const(void)[] buf, SocketFlags flags, Address to)
	{
		_events &= ~EventType._CANNOT_WRITE;
		return super.sendTo(buf, flags, to);
	}
	
	override long sendTo(const(void)[] buf, Address to)
	{
		_events &= ~EventType._CANNOT_WRITE;
		return super.sendTo(buf, to);
	}
	
	override long sendTo(const(void)[] buf, SocketFlags flags)
	{
		_events &= ~EventType._CANNOT_WRITE;
		return super.sendTo(buf, flags);
	}
	
	override long sendTo(const(void)[] buf)
	{
		_events &= ~EventType._CANNOT_WRITE;
		return super.sendTo(buf);
	}

	override Socket accept()
	{
		_events &= ~EventType._CANNOT_ACCEPT;
		return super.accept();
	}
	
	
	private:
	
	EventType _events;
	RegisterEventCallback _callback;
	
	
	void _cando(EventType can)
	{
		_events &= ~(can << 16);
	}
	
	void _cannotdo(EventType cannot)
	{
		_events |= (cannot << 16);
	}
	
	bool _ifcando(EventType ifcan)
	{
		return !(_events & (ifcan << 16));
	}
	
	
	long _peekreceiveclose()
	{
		byte[1] onebyte;
		return Socket.receive(onebyte, SocketFlags.PEEK);
	}
	
	
	void _tgotEvent(EventType type, int err)
	{
		debug(splat)
		{
			if(type == EventType.READ)
				printf("  {READ:%p}\n", cast(void*)this);
			else if(type == EventType.WRITE)
				printf("  {WRITE:%p}\n", cast(void*)this);
			else if(type == EventType.CONNECT)
				printf("  {CONNECT:%p}\n", cast(void*)this);
			else if(type == EventType.CLOSE)
				printf("  {CLOSE:%p}\n", cast(void*)this);
			else if(type == EventType.ACCEPT)
				printf("  {ACCEPT:%p}\n", cast(void*)this);
		}
		
		if(_callback)
			_callback(this, type, err);
	}
}


/// Asynchronous TCP socket shortcut.
class AsyncTcpSocket: AsyncSocket
{
	///
	this(AddressFamily family)
	{
		super(family, SocketType.STREAM, ProtocolType.TCP);
	}
	
	/// ditto
	this()
	{
		this(cast(AddressFamily)AddressFamily.INET);
	}
	
	/// ditto
	// Shortcut.
	this(EventType events, RegisterEventCallback eventCallback)
	{
		this(cast(AddressFamily)AddressFamily.INET);
		event(events, eventCallback);
	}
	
	/// ditto
	// Shortcut.
	this(Address connectTo, EventType events, RegisterEventCallback eventCallback)
	{
		this(connectTo.addressFamily());
		event(events, eventCallback);
		connect(connectTo);
	}
}


/// Asynchronous UDP socket shortcut.
class AsyncUdpSocket: AsyncSocket
{
	///
	this(AddressFamily family)
	{
		super(family, SocketType.DGRAM, ProtocolType.UDP);
	}
	
	/// ditto
	this()
	{
		this(cast(AddressFamily)AddressFamily.INET);
	}
	
	/// ditto
	// Shortcut.
	this(EventType events, RegisterEventCallback eventCallback)
	{
		this(cast(AddressFamily)AddressFamily.INET);
		event(events, eventCallback);
	}
}


private void _tgetHostErr()
{
	throw new Exception("Get host failure");
}


/**
	Callback type for host resolve event.
	Params:
		inetHost = the InternetHost/NetHost of the resolved host, or null.
		err = an error code, or 0 if successful; if 0, inetHost will be null.
**/
alias void delegate(spdInternetHost inetHost, int err) GetHostCallback;


/// Returned from asyncGetHost functions.
class GetHost
{
	/// Cancel the get-host operation.
	void cancel()
	{
		_tcallback = null;
	}
	
	
	private:
	GetHostCallback _tcallback;
	GetHost _tnext;
	spdInternetHost _tinetHost;
	
	bool _tbyname; // false == by addr
	union
	{
		uint _taddr;
		char[] _tname;
	}
	
	
	void _tgotEvent()
	{
		if(!_tcallback) // If cancel().
			return;
		
		if(!_tinetHost)
		{
			_tcallback(null, -1); // ?
			return;
		}
		
		_tcallback(_tinetHost, 0);
	}
	
	
	this()
	{
	}
}


/// Asynchronously resolve host information from a hostname; the callback depends on run().
GetHost asyncGetHostByName(char[] name, GetHostCallback callback)
{
	GetHost gh;
	gh = new GetHost;
	version(NO_THREADS)
	{
		spdInternetHost ih;
		ih = new spdInternetHost;
		if(ih.getHostByName(name))
		{
			gh.inetHost = ih;
		}
	}
	else
	{
		gh._tcallback = callback;
		gh._tbyname = true;
		gh._tname = name;
		_tgethost(gh);
	}
	return gh;
}


/// Asynchronously resolve host information from an IPv4 address; the callback depends on run().
GetHost asyncGetHostByAddr(uint addr, GetHostCallback callback)
{
	GetHost gh;
	gh = new GetHost;
	version(NO_THREADS)
	{
		spdInternetHost ih;
		ih = new spdInternetHost;
		if(ih.getHostByAddr(addr))
		{
			gh.inetHost = ih;
		}
	}
	else
	{
		gh._tcallback = callback;
		gh._tbyname = false;
		gh._taddr = addr;
		_tgethost(gh);
	}
	return gh;
}

/// ditto
GetHost asyncGetHostByAddr(char[] addr, GetHostCallback callback)
{
	uint uiaddr;
	uiaddr = spdInternetAddress.parse(addr);
	if(spdInternetAddress.ADDR_NONE == uiaddr)
		_tgetHostErr();
	return asyncGetHostByAddr(uiaddr, callback);
}


version = THSLEEP;


version(THSLEEP)
{
	version(Windows)
	{
		private void _tthsleep()
		{
			Sleep(200); // 0.2 secs.
		}
	}
	else
	{
		private extern(C) int usleep(uint microseconds);
		
		private void _tthsleep()
		{
			usleep(200_000); // 0.2 secs.
		}
	}
}


private void _tgethost(GetHost gh)
{
	debug(splat)
	{
		printf("  {GETHOST:%p}\n", cast(void*)gh);
	}
	
	//synchronized
	{
		gh._tnext = null;
		
		if(!_ththread)
		{
			_ththread = new Thread(&_ththreadproc);
			_thnext = _thaddto = gh;
			_ththread.start();
			return;
		}
		
		synchronized(_ththread)
		{
			if(!_thaddto)
			{
				version(SPLAT_HACK_PRINTF)
					printf(""); // Without this, the thread never sees this host.
					
				_thnext = _thaddto = gh;
				
				version(THSLEEP)
				{
				}
				else
				{
					debug(splat)
					{
						printf("  {RESUMING:_ththreadproc}\n");
					}
					
					_ththread.resume();
				}
			}
			else
			{
				_thaddto._tnext = gh;
				_thaddto = gh;
			}
		}
	}
}


private void _dothreadproc()
{
	GetHost gh;
	spdInternetHost ih;
	for(;;)
	{
		synchronized
		{
			gh = _thnext;
		}
		
		if(!gh)
		{
			version(THSLEEP)
			{
				_tthsleep();
			}
			else
			{
				debug(splat)
				{
					printf("  {PAUSE:_ththreadproc}\n");
				}
				
				_ththread.pause();
				
				debug(splat)
				{
					printf("  {RESUMED:_ththreadproc}\n");
				}
			}
			continue;
		}
		
		if(gh._tcallback) // If not cancel()..
		{
			try
			{
				ih = new spdInternetHost;
				if(gh._tbyname)
				{
					if(ih.getHostByName(gh._tname))
						gh._tinetHost = ih;
				}
				else // byaddr
				{
					if(ih.getHostByAddr(gh._taddr))
						gh._tinetHost = ih;
				}
				
				debug(splat)
				{
					printf("  {GOTHOST:%p} %s\n", cast(void*)gh, gh._tinetHost ? "true".ptr : "false".ptr);
				}
			}
			catch
			{
			}
		}
		
		_thpn(gh);
	}
}

private void _ththreadproc()
{
	_dothreadproc();
}

// GDC 0.19 segfaults if this isn't in a function; might have to do with synchronized() in a loop.
private void _thpn(GetHost gh)
{
	synchronized(_ththread)
	{
		assert(gh is _thnext);
		
		debug(splat)
		{
			printf("  {DONEHOST:%p}\n", cast(void*)gh);
		}
		
		_thnext = _thnext._tnext;
		if(!_thnext)
			_thaddto = null;
		
		gh._tnext = null;
		if(_thfinlast)
			_thfinlast._tnext = gh;
		else
			_thfinnext = gh;
		_thfinlast = gh;
	}
}


private GetHost _tnextDoneHost()
{
	GetHost gh;
	
	synchronized gh = _thfinnext;
	if(!gh)
		return null;
	
	synchronized(_ththread)
	{
		gh = _thfinnext;
		if(gh)
		{
			_thfinnext = _thfinnext._tnext;
			if(!_thfinnext)
				_thfinlast = null;
			gh._tnext = null;
		}
	}
	
	return gh;
}


private bool _areHosts()
{
	return _thnext || _thfinnext;
}


/// Buffering socket I/O.
class SocketQueue
{
	///
	this(Socket sock)
	in
	{
		assert(sock !is null);
	}
	body
	{
		this.sock = sock;
	}
	
	
	/// Property: get the socket of this queue.
	final Socket socket() // getter
	{
		return sock;
	}
	
	
	/// Resets the buffers.
	void reset()
	{
		writebuf = null;
		readbuf = null;
	}
	
	// DMD 0.92 says error: function toString overrides but is not covariant with toString
	override string toString()
	{
		return cast(string)peek();
	}
	
	
	/// Peek at some or all of the received data but leave it in the queue. May return less than requested.
	void[] peek()
	{
		return readbuf[0 .. rpos];
	}
	
	/// ditto
	void[] peek(uint len)
	{
		if(len >= rpos)
			return peek();
		
		return readbuf[0 .. len];
	}
	
	
	/// Returns: some or all of the received data and removes this amount from the queue. May return less than requested.
	void[] receive()
	{
		ubyte[] result;
		
		result = readbuf[0 .. rpos];
		readbuf = null;
		rpos = 0;
		
		return result;
	}
	
	/// ditto
	void[] receive(uint len)
	{
		if(len >= rpos)
			return receive();
		
		ubyte[] result;
		
		result = readbuf[0 .. len];
		readbuf = readbuf[len .. readbuf.length];
		rpos -= len;
		
		return result;
	}
	
	
	/// Add data to the queue and send it over this socket.
	void send(void[] buf)
	{
		if(canwrite)
		{
			assert(!writebuf.length);
			
			long st;
			if(buf.length > 4096)
				st = 4096;
			else
				st = buf.length;
			
			st = sock.send(buf[0 .. st]);
			if(st > 0)
			{
				if(buf.length - st)
				{
					// dup so it can be appended to.
					writebuf = (cast(ubyte[])buf)[st .. buf.length].dup;
				}
			}
			else
			{
				// dup so it can be appended to.
				writebuf = (cast(ubyte[])buf).dup;
			}
			
			//canwrite = false;
		}
		else
		{
			writebuf ~= cast(ubyte[])buf;
		}
	}
	
	
	/// Property: get the number of bytes in send buffer.
	ulong sendBytes()
	{
		return writebuf.length;
	}
	
	
	/// Property: get the number of bytes in recv buffer.
	uint receiveBytes()
	{
		return rpos;
	}
	
	
	/// Call on a read event so that incoming data may be buffered.
	void readEvent()
	{
		if(readbuf.length - rpos < 1024)
			readbuf.length = readbuf.length + 2048;
		
		long rd = sock.receive(readbuf[rpos .. readbuf.length]);
		if(rd > 0)
			rpos += cast(uint)rd;
	}
	
	
	/// Call on a write event so that buffered outgoing data may be sent.
	void writeEvent()
	{
		if(writebuf.length)
		{
			ubyte[] buf;
			
			if(writebuf.length > 4096)
				buf = writebuf[0 .. 4096];
			else
				buf = writebuf;
			
			long st = sock.send(buf);
			if(st > 0)
				writebuf = writebuf[st .. writebuf.length];
		}
		else
		{
			//canwrite = true;
		}
	}
	
	
	/**
		Shortcut function for AsyncSocket.
		Automatically calls readEvent and writeEvent as needed.
		Same signature as RegisterEventCallback for simplicity.
	**/
	void event(Socket _sock, EventType type, int err)
	in
	{
		assert(_sock is sock);
	}
	body
	{
		switch(type)
		{
			case EventType.READ:
				readEvent();
				break;
			
			case EventType.WRITE:
				writeEvent();
				break;
			
			default: ;
		}
	}
	
	
	deprecated
	{
		alias receiveBytes recvBytes;
		alias receive recv;
	}
	
	
	private:
	ubyte[] writebuf;
	ubyte[] readbuf;
	uint rpos;
	Socket sock;
	
	
	bool canwrite()
	{
		return writebuf.length == 0;
	}
}


size_t getNumberOfAsyncSockets()
{
	return _tallEvents.length;
}


size_t getNumberOfTimers()
{
	return _tcount;
}


private:

Timer _tfirst, _tlast;
size_t _tcount = 0;


Timer _tnext()
{
	spdTime lowest = cast(spdTime)((spdTime.init + 0).max); // + 1 converts to the underlying arithmetic type to get the real max.
	Timer t, tlowest;
	for(t = _tfirst; t; t = t._tnext)
	{
		if(t._talarm < lowest)
		{
			tlowest = t;
			lowest = t._talarm;
		}
	}
	return tlowest;
}


void _tadd(Timer t)
in
{
	assert(t !is null);
	assert(t._ttimeout);
	assert(t._tprev is null);
	assert(t._tnext is null);
	assert(t._talarm == t._TALARM_INIT);
}
body
{
	t._talarm = cast(spdTime)(stdCurrentTime() + t._ttimeout);
	
	t._tprev = _tlast;
	_tlast = t;
	if(!_tfirst)
		_tfirst = t;
	else
		t._tprev._tnext = t;
	
	_tcount++;
}


void _tremove(Timer t)
in
{
	assert(t !is null);
	assert(t._talarm != t._TALARM_INIT);
}
body
{
	t._talarm = t._TALARM_INIT;
	
	if(t._tprev)
		t._tprev._tnext = t._tnext;
	else
		_tfirst = t._tnext;
	
	if(t._tnext)
		t._tnext._tprev = t._tprev;
	else
		_tlast = t._tprev;
	
	t._tprev = null;
	t._tnext = null;
	
	if(_tcount)
		_tcount--;
}


template _tTicks()
{
	uint _tticksToSecs(spdTime ticks) { return cast(uint)(ticks / 1000); }
	uint _tticksToMs(spdTime ticks) { return cast(uint)ticks; }
	uint _tticksToMicrosecs(spdTime ticks) { return cast(uint)(cast(double)ticks / cast(double)1000 * cast(double)1_000_000); }
	spdTime _tsecsToTicks(uint secs) { return cast(spdTime)(secs * 1000); }
	spdTime _tmsToTicks(uint ms) { return cast(spdTime)ms; }
}

alias _tTicks!()._tticksToSecs _tticksToSecs;
alias _tTicks!()._tticksToMs _tticksToMs;
alias _tTicks!()._tticksToMicrosecs _tticksToMicrosecs;
alias _tTicks!()._tsecsToTicks _tsecsToTicks;
alias _tTicks!()._tmsToTicks _tmsToTicks;


unittest
{
	assert(_tsecsToTicks(_tticksToSecs(543253)) == _tsecsToTicks(_tticksToSecs(543253)));
	assert(_tmsToTicks(_tticksToMs(3445723)) == _tmsToTicks(_tticksToMs(3445723)));
}


void _tticksToTimeval(spdTime ticks, spdMyTimeval* tv)
{
	tv.seconds = _tticksToSecs(ticks);
	ticks -= _tsecsToTicks(to!uint(tv.seconds));
	tv.microseconds = _tticksToMicrosecs(ticks);
}

AsyncSocket[socket_t] _tallEvents;

Thread _ththread;
GetHost _thnext, _thaddto;
GetHost _thfinnext, _thfinlast;

bool _texit = false;