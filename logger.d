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

shared interface ILogger {
	void info(string msg);
	void error(string msg);
	void warning(string msg);
	void development(string msg);
	void fatal(string msg);
}

shared(ILogger) getSimpleLogger()
{
	static shared ILogger instance;

	if(!instance)
	{
		synchronized
		{
			if(!instance)
				instance = new shared(SimpleLogger)();
		}
	}
	
	return instance;
}

shared class SimpleLogger: AbstractLogger{
	this(){
		super();
	}
	
	override string dateStringImpl(SysTime systime){
		return systime.toISOExtString();
	}
}

private enum LogLevel {
	ALL = 6,
	DEBUG = 5,
	INFO = 4,
	WARN = 3,
	ERROR = 2,
	FATAL = 1,
	OFF = 0
}

shared abstract class AbstractLogger: ILogger {
	private LogLevel[string] properties;
	private string msgDelimiter;
	private LogLevel logLevel = LogLevel.ALL;
	private bool logAll,disableLog;

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
			properties[strip(arr[0])]=to!LogLevel(strip(arr[1]));
		}
		logLevel = properties["quickserver.logger.level"];
		logAll = logLevel == LogLevel.ALL;
		disableLog = logLevel == LogLevel.OFF;
		writeln("Disable Log: "~to!string(disableLog)~"\t"~"Log All: "~to!string(logAll)~"\t"~"Log level: "~to!string(logLevel));
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
	
	private bool shouldLog(LogLevel level){
		return (!disableLog && (logAll || level <= logLevel));
	}
	
	public override void info(string msg){
		if(shouldLog(LogLevel.INFO))
			append(createLogEntry(LogLevel.INFO,msg));
	}
	
	public override void error(string msg){
		if(shouldLog(LogLevel.ERROR))
			append(createLogEntry(LogLevel.ERROR,msg));
	}
	
	public override void warning(string msg){
		if(shouldLog(LogLevel.WARN))
			append(createLogEntry(LogLevel.WARN,msg));
	}
	
	public override void development(string msg){
		if(shouldLog(LogLevel.DEBUG))
			append(createLogEntry(LogLevel.DEBUG,msg));
	}
	
	public override void fatal(string msg){
		if(shouldLog(LogLevel.FATAL))
			append(createLogEntry(LogLevel.FATAL,msg));
	}
}
