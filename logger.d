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

module quickserver.logger;

import std.conv, std.socket, std.stdio, core.thread, std.datetime, std.file, std.string,std.regex;

interface ILogger {
	void info(string msg);
	void error(string msg);
	void warning(string msg);
	void dev(string msg);
	void critical(string msg);
}

class LoggerFactory {
	private static ILogger logger;
	
	ILogger getSimpleLogger(){
		synchronized {
			if(logger is null)
				logger = new SimpleLogger();
			return logger;
		}
	}
}

class SimpleLogger: AbstractLogger{
	this(){
		super();
	}
	
	override string dateStringImpl(SysTime systime){
		return systime.toISOExtString();
	}
}

private enum LogLevel {
	ALL,
	INFO,
	WARNING,
	ERROR,
	CRITICAL,
	DEBUG
}

abstract class AbstractLogger: ILogger {
	string[string] properties;
	
	string msgDelimiter;
	
	LogLevel logLevel = LogLevel.ALL;

	this(){
		scope(failure)
			throw new Exception("Failed in AbstractLogger constructor");
		msgDelimiter = " ";
		string props = to!string(read("logger.properties"));
		string[] propsArr = splitLines(props);
		foreach(propertyLine; propsArr){
			scope(failure)
				throw new Exception("Malformed property: "~propertyLine);
			string[] arr = explode(propertyLine,'=');
			properties[strip(arr[0])]=strip(arr[1]);
		}
		int level = to!int(properties["quickserver.logger.level"]);
		logLevel = cast(LogLevel)level;
	}
	
	/**
	 * Should use library function but regex is too hard to understand.
	 * This has been taken from d lang forum.
	 * */
	private string[] explode(in string source, char separator) {
		typeof(return) result;
		size_t prev = 0;
		foreach (i, c; source) {
			if (c == separator) {
				result ~= source[prev .. i];
				prev = i + 1;
			}
		}
		result ~= source[prev .. $];
		return result;
	}
	
	private static ILogger logger;
	
	static ILogger getSimpleLogger(){
		synchronized {
			if(logger is null)
				logger = new SimpleLogger();
			return logger;
		}
	}
	
	public abstract string dateStringImpl(SysTime systime);
	
	private void append(string msg){
		writeln(msg);
	}
	
	private string datestring(){
		auto systime = Clock.currTime(UTC());
		return dateStringImpl(systime);
	}
	
	private string createLogEntry(LogLevel type, string msg){
		string dateStr = datestring();
		string s = dateStr~" "~to!string(type)~":"~msgDelimiter~msg; 
		return s;
	}
	
	override void info(string msg){
		if(logLevel == LogLevel.ALL || logLevel==LogLevel.INFO)
			append(createLogEntry(LogLevel.INFO,msg));
	}
	
	override void error(string msg){
		if(logLevel == LogLevel.ALL || logLevel == LogLevel.ERROR)
			append(createLogEntry(LogLevel.ERROR,msg));
	}
	
	override void warning(string msg){
		if(logLevel == LogLevel.ALL || logLevel == LogLevel.WARNING)
			append(createLogEntry(LogLevel.WARNING,msg));
	}
	
	override void dev(string msg){
		if(logLevel == LogLevel.ALL || logLevel == LogLevel.DEBUG)
			append(createLogEntry(LogLevel.DEBUG,msg));
	}
	
	override void critical(string msg){
		if(logLevel == LogLevel.ALL || logLevel == LogLevel.CRITICAL)
			append(createLogEntry(LogLevel.CRITICAL,msg));
	}
}
