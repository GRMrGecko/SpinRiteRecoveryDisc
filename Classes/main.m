//
//  main.m
//  SpinRiteRecoveryDisc
//
//  Created by Mr. Gecko on 2/2/13.
//  Copyright (c) 2013 Mr. Gecko's Media (James Coleman). All rights reserved. http://mrgeckosmedia.com/
//
//  Permission to use, copy, modify, and/or distribute this software for any purpose
//  with or without fee is hereby granted, provided that the above copyright notice
//  and this permission notice appear in all copies.
//
//  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
//  REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
//  FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT,
//  OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE,
//  DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS
//  ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
//

#import <Foundation/Foundation.h>

NSString * const MGMDiskUtilPath = @"/usr/sbin/diskutil";
NSString * const MGMHDIUtillPath = @"/usr/bin/hdiutil";
NSString * const MGMInstallerPath = @"/usr/sbin/installer";
NSString * const MGMBlessPath = @"/usr/sbin/bless";
NSString * const MGMRMPath = @"/bin/rm";
NSString * const MGMLNPath = @"/bin/ln";
NSString * const MGMCHMODPath = @"/bin/chmod";
NSString * const MGMCHOWNPath = @"/bin/chown";

NSData *runCommand(NSString *command, NSArray *arguments) {
	NSTask *task = [NSTask new];
	[task setLaunchPath:command];
	[task setArguments:arguments];
	NSPipe *outPipe = [NSPipe new];
	[task setStandardError:outPipe];
	[task setStandardOutput:outPipe];
	[task setEnvironment:[NSDictionary dictionaryWithObject:@"CM_BUILD" forKey:@"CM_BUILD"]];
	[task launch];
	[task waitUntilExit];
	NSData *returnData = [[outPipe fileHandleForReading] readDataToEndOfFile];
	[task release];
	[outPipe release];
	return returnData;
}


void MGMPrintV(NSString *format, va_list args) {
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	if (![format hasSuffix:@"\n"])
		format = [format stringByAppendingString:@"\n"];
	NSString *message = [[[NSString alloc] initWithFormat:format arguments:args] autorelease];
	fwrite([message UTF8String], 1, [message length], stdout);
	[pool drain];
}
void MGMPrint(NSString *format, ...) {
	va_list ap;
	va_start(ap, format);
	MGMPrintV(format, ap);
	va_end(ap);
}

int main(int argc, const char * argv[]) {
	NSAutoreleasePool *pool = [NSAutoreleasePool new];
	
	if (![NSUserName() isEqual:@"root"]) {
		MGMPrint(@"This program requires that you run it as root. To do so, run this command with sudo infront of it. It will request your password and then continue.");
		[pool drain];
		exit(1);
	}
	
	/*MGMPrint(@"Welcome to Mr. Gecko's SpinRite Disk Maker.");
	MGMPrint(@"This utility will create a new DMG with the contents the Recovery Drive modified to include VirtualBox and SpinRite. VirtualBox will run SpinRite on your Hard Disk.");
	MGMPrint(@"Press enter to continue. To exit, push control-c.");
	char *ignore = malloc(1);
	scanf("%c", ignore);
	free(ignore);*/
	
	NSFileManager *manager = [NSFileManager defaultManager];
	
	NSData *data = runCommand(MGMDiskUtilPath, [NSArray arrayWithObjects:@"list", @"-plist", nil]);
	NSString *error = nil;
	NSDictionary *diskList = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:NSPropertyListImmutable format:nil errorDescription:&error];
	if (error!=nil) {
		MGMPrint(@"Encountered error parsing disk list: %@", [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
		[pool drain];
		exit(1);
	}
	
	NSString *recoveryPartition = nil;
	NSString *mountPoint = nil;
	
	NSArray *disksAndPartitions = [diskList objectForKey:@"AllDisksAndPartitions"];
	for (unsigned int i=0; i<[disksAndPartitions count]; i++) {
		NSArray *partitions = [[disksAndPartitions objectAtIndex:i] objectForKey:@"Partitions"];
		if (partitions!=nil) {
			for (unsigned int p=0; p<[partitions count]; p++) {
				if ([[[partitions objectAtIndex:p] objectForKey:@"VolumeName"] isEqual:@"Recovery HD"]) {
					recoveryPartition = [NSString stringWithFormat:@"/dev/%@", [[partitions objectAtIndex:p] objectForKey:@"DeviceIdentifier"]];
					mountPoint = [[partitions objectAtIndex:p] objectForKey:@"MountPoint"];
					break;
				}
			}
			if (recoveryPartition!=nil)
				break;
		}
	}
	
	if (recoveryPartition==nil) {
		MGMPrint(@"Your system does not appear to have a Recovery Partition.");
		[pool drain];
		exit(1);
	}
	
	MGMPrint(@"Found Recovery Partition at %@.", recoveryPartition);
	
	if (mountPoint==nil) {
		runCommand(MGMDiskUtilPath, [NSArray arrayWithObjects:@"mount", recoveryPartition, nil]);
		
		NSData *data = runCommand(MGMDiskUtilPath, [NSArray arrayWithObjects:@"list", @"-plist", nil]);
		NSString *error = nil;
		NSDictionary *diskList = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:NSPropertyListImmutable format:nil errorDescription:&error];
		if (error!=nil) {
			MGMPrint(@"Encountered error parsing disk list: %@", [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
			[pool drain];
			exit(1);
		}
		
		NSArray *disksAndPartitions = [diskList objectForKey:@"AllDisksAndPartitions"];
		for (unsigned int i=0; i<[disksAndPartitions count]; i++) {
			NSArray *partitions = [[disksAndPartitions objectAtIndex:i] objectForKey:@"Partitions"];
			if (partitions!=nil) {
				for (unsigned int p=0; p<[partitions count]; p++) {
					if ([[[partitions objectAtIndex:p] objectForKey:@"VolumeName"] isEqual:@"Recovery HD"]) {
						mountPoint = [[partitions objectAtIndex:p] objectForKey:@"MountPoint"];
						break;
					}
				}
				if (recoveryPartition!=nil)
					break;
			}
		}
	}
	if (mountPoint==nil) {
		MGMPrint(@"Failed to mount Recovery Partition.");
		[pool drain];
		exit(1);
	}
	
	NSString *spinRiteMountPoint = nil;
	
	if (![manager fileExistsAtPath:@"/tmp/SpinRite.dmg"]) {
		NSData *data = runCommand(MGMHDIUtillPath, [NSArray arrayWithObjects:@"create", @"-srcfolder", mountPoint, @"-format", @"UDRW", @"-size", @"680m", @"-fs", @"HFS+", @"-layout", @"SPUD", @"-volname", @"SpinRite", @"-attach", @"-plist", @"/tmp/SpinRite.dmg", nil]);
		NSString *error = nil;
		NSDictionary *info = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:NSPropertyListImmutable format:nil errorDescription:&error];
		if (error!=nil) {
			MGMPrint(@"Encountered error parsing image info: %@", [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
			[manager removeItemAtPath:@"/tmp/SpinRite.dmg" error:nil];
			runCommand(MGMDiskUtilPath, [NSArray arrayWithObjects:@"unmount", recoveryPartition, nil]);
			[pool drain];
			exit(1);
		}
		
		NSArray *systemEntities = [info objectForKey:@"system-entities"];
		for (unsigned int i=0; i<[systemEntities count]; i++) {
			spinRiteMountPoint = [[systemEntities objectAtIndex:i] objectForKey:@"mount-point"];
			if (spinRiteMountPoint!=nil) {
				break;
			}
		}
	} else {
		NSData *data = runCommand(MGMHDIUtillPath, [NSArray arrayWithObjects:@"attach", @"-plist", @"/tmp/SpinRite.dmg", nil]);
		NSString *error = nil;
		NSDictionary *info = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:NSPropertyListImmutable format:nil errorDescription:&error];
		if (error!=nil) {
			MGMPrint(@"Encountered error parsing image info: %@", [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
			[manager removeItemAtPath:@"/tmp/SpinRite.dmg" error:nil];
			runCommand(MGMDiskUtilPath, [NSArray arrayWithObjects:@"unmount", recoveryPartition, nil]);
			[pool drain];
			exit(1);
		}
		
		NSArray *systemEntities = [info objectForKey:@"system-entities"];
		for (unsigned int i=0; i<[systemEntities count]; i++) {
			spinRiteMountPoint = [[systemEntities objectAtIndex:i] objectForKey:@"mount-point"];
			if (spinRiteMountPoint!=nil) {
				break;
			}
		}
	}
	runCommand(MGMDiskUtilPath, [NSArray arrayWithObjects:@"unmount", recoveryPartition, nil]);
	
	if (spinRiteMountPoint==nil) {
		MGMPrint(@"Failed to make a disk image of the Recovery Partition.");
		[manager removeItemAtPath:@"/tmp/SpinRite.dmg" error:nil];
		[pool drain];
		exit(1);
	}
	
	[manager removeItemAtPath:[spinRiteMountPoint stringByAppendingPathComponent:@"com.apple.boot.S"] error:nil];
	runCommand(MGMBlessPath, [NSArray arrayWithObjects:[NSString stringWithFormat:@"--folder=%@", [spinRiteMountPoint stringByAppendingPathComponent:@"com.apple.recovery.boot"]], [NSString stringWithFormat:@"--file=%@", [[spinRiteMountPoint stringByAppendingPathComponent:@"com.apple.recovery.boot"] stringByAppendingPathComponent:@"boot.efi"]], nil]); // May God bless this folder so that this disk will boot amazingly.
	
	NSString *baseSystemMountPoint = nil;
	
	if (![manager fileExistsAtPath:@"/tmp/BaseSystem.dmg"]) {
		NSString *originalBaseSystemMountPoint = nil;
		NSData *data = runCommand(MGMHDIUtillPath, [NSArray arrayWithObjects:@"attach", @"-plist", [[spinRiteMountPoint stringByAppendingPathComponent:@"com.apple.recovery.boot"] stringByAppendingPathComponent:@"BaseSystem.dmg"], nil]);
		NSString *error = nil;
		NSDictionary *info = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:NSPropertyListImmutable format:nil errorDescription:&error];
		if (error!=nil) {
			MGMPrint(@"Encountered error parsing image info: %@", [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
			runCommand(MGMDiskUtilPath, [NSArray arrayWithObjects:@"unmount", recoveryPartition, nil]);
			[pool drain];
			exit(1);
		}
		
		NSArray *systemEntities = [info objectForKey:@"system-entities"];
		for (unsigned int i=0; i<[systemEntities count]; i++) {
			originalBaseSystemMountPoint = [[systemEntities objectAtIndex:i] objectForKey:@"mount-point"];
			if (originalBaseSystemMountPoint!=nil) {
				break;
			}
		}
		
		if (originalBaseSystemMountPoint==nil) {
			MGMPrint(@"Unable to mount Base System from Recovery Image.");
			[manager removeItemAtPath:@"/tmp/BaseSystem.dmg" error:nil];
			[pool drain];
			exit(1);
		}
		
		data = runCommand(MGMHDIUtillPath, [NSArray arrayWithObjects:@"create", @"-srcfolder", originalBaseSystemMountPoint, @"-format", @"UDRW", @"-size", @"2g", @"-fs", @"HFS+", @"-layout", @"SPUD", @"-volname", @"BaseSystem", @"-attach", @"-plist", @"/tmp/BaseSystem.dmg", nil]);
		error = nil;
		info = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:NSPropertyListImmutable format:nil errorDescription:&error];
		if (error!=nil) {
			MGMPrint(@"Encountered error parsing image info: %@", [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
			[manager removeItemAtPath:@"/tmp/BaseSystem.dmg" error:nil];
			runCommand(MGMHDIUtillPath, [NSArray arrayWithObjects:@"detach", originalBaseSystemMountPoint, nil]);
			[pool drain];
			exit(1);
		}
		
		systemEntities = [info objectForKey:@"system-entities"];
		for (unsigned int i=0; i<[systemEntities count]; i++) {
			baseSystemMountPoint = [[systemEntities objectAtIndex:i] objectForKey:@"mount-point"];
			if (baseSystemMountPoint!=nil) {
				break;
			}
		}
		runCommand(MGMHDIUtillPath, [NSArray arrayWithObjects:@"detach", originalBaseSystemMountPoint, nil]);
	} else {
		NSData *data = runCommand(MGMHDIUtillPath, [NSArray arrayWithObjects:@"attach", @"-plist", @"/tmp/BaseSystem.dmg", nil]);
		NSString *error = nil;
		NSDictionary *info = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:NSPropertyListImmutable format:nil errorDescription:&error];
		if (error!=nil) {
			MGMPrint(@"Encountered error parsing image info: %@", [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
			[manager removeItemAtPath:@"/tmp/BaseSystem.dmg" error:nil];
			[pool drain];
			exit(1);
		}
		
		NSArray *systemEntities = [info objectForKey:@"system-entities"];
		for (unsigned int i=0; i<[systemEntities count]; i++) {
			baseSystemMountPoint = [[systemEntities objectAtIndex:i] objectForKey:@"mount-point"];
			if (baseSystemMountPoint!=nil) {
				break;
			}
		}
	}
	
	if (baseSystemMountPoint==nil) {
		MGMPrint(@"Unable to mount Base System.");
		[manager removeItemAtPath:@"/tmp/BaseSystem.dmg" error:nil];
		[pool drain];
		exit(1);
	}
	
	runCommand(MGMBlessPath, [NSArray arrayWithObjects:[NSString stringWithFormat:@"--folder=%@", [baseSystemMountPoint stringByAppendingString:@"/System/Library/CoreServices"]], [NSString stringWithFormat:@"--file=%@", [baseSystemMountPoint stringByAppendingString:@"/System/Library/CoreServices/boot.efi"]], nil]); // May God bless this folder so that this disk will boot amazingly.
	
	//[manager removeItemAtPath:[baseSystemMountPoint stringByAppendingPathComponent:@"Install OS X Mountain Lion.app"] error:nil];
	//[manager removeItemAtPath:[[baseSystemMountPoint stringByAppendingPathComponent:@"System"] stringByAppendingPathComponent:@"Installation"] error:nil];
	
	MGMPrint(@"Please download VirtualBox, drag the DMG file here, and push enter.");
	char *virtualBoxString = malloc(512);
	scanf("%s", virtualBoxString);
	NSString *virtualBoxPath = [[NSString stringWithUTF8String:virtualBoxString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	free(virtualBoxString);
	NSString *virtualBoxMountPoint = nil;
	
	data = runCommand(MGMHDIUtillPath, [NSArray arrayWithObjects:@"attach", @"-plist", virtualBoxPath, nil]);
	error = nil;
	NSDictionary *info = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:NSPropertyListImmutable format:nil errorDescription:&error];
	if (error!=nil) {
		MGMPrint(@"Encountered error parsing image info: %@", [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
		[pool drain];
		exit(1);
	}
	
	NSArray *systemEntities = [info objectForKey:@"system-entities"];
	for (unsigned int i=0; i<[systemEntities count]; i++) {
		virtualBoxMountPoint = [[systemEntities objectAtIndex:i] objectForKey:@"mount-point"];
		if (virtualBoxMountPoint!=nil) {
			break;
		}
	}
	
	if (virtualBoxMountPoint==nil || ![manager fileExistsAtPath:[virtualBoxMountPoint stringByAppendingPathComponent:@"VirtualBox.pkg"]]) {
		MGMPrint(@"Unable to mount VirtualBox.");
		[pool drain];
		exit(1);
	}
	
	runCommand(MGMInstallerPath, [NSArray arrayWithObjects:@"-pkg", [virtualBoxMountPoint stringByAppendingPathComponent:@"VirtualBox.pkg"], @"-target", baseSystemMountPoint, nil]);
	
	/*NSString *extensionsPath = [[baseSystemMountPoint stringByAppendingPathComponent:@"Library"] stringByAppendingPathComponent:@"Extensions"];
	[manager removeItemAtPath:[extensionsPath stringByAppendingPathComponent:@"VBoxDrv.kext"] error:nil];
	[manager removeItemAtPath:[extensionsPath stringByAppendingPathComponent:@"VBoxNetAdp.kext"] error:nil];
	[manager removeItemAtPath:[extensionsPath stringByAppendingPathComponent:@"VBoxNetFlt.kext"] error:nil];
	[manager removeItemAtPath:[extensionsPath stringByAppendingPathComponent:@"VBoxUSB.kext"] error:nil];*/
	
	//VirtualBox shell scripts fail on my computer. I think it's related to me customizing the ls command. So here is a custom version of those shell scripts. Because the recovery partition is 64bit only, I'm removing x86 and only linking x86_64.
	NSString *virtualBoxBinaryPath = [baseSystemMountPoint stringByAppendingString:@"/Applications/VirtualBox.app/Contents/MacOS/"];
	NSArray *files = [manager contentsOfDirectoryAtPath:virtualBoxBinaryPath error:nil];
	for (unsigned int i=0; i<[files count]; i++) {
		NSString *file = [virtualBoxBinaryPath stringByAppendingString:[files objectAtIndex:i]];
		if ([file hasSuffix:@"-amd64"]) {
			NSString *newFile = [file stringByReplacingOccurrencesOfString:@"-amd64" withString:@""];
			runCommand(MGMRMPath, [NSArray arrayWithObjects:@"-f", newFile, nil]);
			runCommand(MGMLNPath, [NSArray arrayWithObjects:@"-vh", file, newFile, nil]);
		} else if ([file hasSuffix:@"-x86"]) {
			runCommand(MGMRMPath, [NSArray arrayWithObjects:@"-f", file, nil]);
		}
	}
	runCommand(MGMCHMODPath, [NSArray arrayWithObjects:@"6755", @"/Applications/VirtualBox.app/Contents/MacOS/VirtualBox", nil]);
	
	runCommand(MGMHDIUtillPath, [NSArray arrayWithObjects:@"detach", virtualBoxMountPoint, nil]);
	
	NSFileHandle *shProfile = [NSFileHandle fileHandleForWritingAtPath:[baseSystemMountPoint stringByAppendingString:@"/etc/profile"]];
	[shProfile writeData:[@"echo \"Available commands are virtualbox, safari, diskutility, and networkutility.\"\n" dataUsingEncoding:NSUTF8StringEncoding]];
	[shProfile closeFile];
	
	runCommand(MGMCHMODPath, [NSArray arrayWithObjects:@"6755", [baseSystemMountPoint stringByAppendingString:@"/usr/bin/VirtualBox"], nil]);
	
	[manager createFileAtPath:[baseSystemMountPoint stringByAppendingString:@"/usr/bin/safari"] contents:[@"#!/bin/bash\n/Applications/Safari.app/Contents/MacOS/Safar\n" dataUsingEncoding:NSUTF8StringEncoding] attributes:nil];
	runCommand(MGMCHMODPath, [NSArray arrayWithObjects:@"755", [baseSystemMountPoint stringByAppendingString:@"/usr/bin/safari"], nil]);
	
	[manager createFileAtPath:[baseSystemMountPoint stringByAppendingString:@"/usr/bin/diskutility"] contents:[@"#!/bin/bash\n/Applications/Disk\\ Utility.app/Contents/MacOS/Disk\\ Utility\n" dataUsingEncoding:NSUTF8StringEncoding] attributes:nil];
	runCommand(MGMCHMODPath, [NSArray arrayWithObjects:@"755", [baseSystemMountPoint stringByAppendingString:@"/usr/bin/diskutility"], nil]);
	
	[manager createFileAtPath:[baseSystemMountPoint stringByAppendingString:@"/usr/bin/networkutility"] contents:[@"#!/bin/bash\n/Applications/Network\\ Utility.app/Contents/MacOS/Network\\ Utility\n" dataUsingEncoding:NSUTF8StringEncoding] attributes:nil];
	runCommand(MGMCHMODPath, [NSArray arrayWithObjects:@"755", [baseSystemMountPoint stringByAppendingString:@"/usr/bin/networkutility"], nil]);
	
	[manager copyItemAtPath:@"/System/Library/Frameworks/AGL.framework" toPath:[baseSystemMountPoint stringByAppendingString:@"/System/Library/Frameworks/AGL.framework"] error:nil];
	
	runCommand(MGMHDIUtillPath, [NSArray arrayWithObjects:@"detach", baseSystemMountPoint, nil]);
	
	data = runCommand(MGMHDIUtillPath, [NSArray arrayWithObjects:@"convert", @"/tmp/BaseSystem.dmg", @"-format", @"UDZO", @"-o", @"/tmp/BaseSystem-out.dmg", @"-plist", nil]);
	error = nil;
	info = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:NSPropertyListImmutable format:nil errorDescription:&error];
	if (error!=nil) {
		MGMPrint(@"Encountered error parsing image info: %@", [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]);
		[manager removeItemAtPath:@"/tmp/BaseSystem-out.dmg" error:nil];
		[pool drain];
		exit(1);
	}
	
	[manager removeItemAtPath:@"/tmp/BaseSystem.dmg" error:nil];
	[manager removeItemAtPath:[[spinRiteMountPoint stringByAppendingPathComponent:@"com.apple.recovery.boot"] stringByAppendingPathComponent:@"BaseSystem.dmg"] error:nil];
	NSError *errorInfo = nil;
	[manager copyItemAtPath:@"/tmp/BaseSystem-out.dmg" toPath:[[spinRiteMountPoint stringByAppendingPathComponent:@"com.apple.recovery.boot"] stringByAppendingPathComponent:@"BaseSystem.dmg"] error:&errorInfo];
	if (errorInfo!=nil) {
		MGMPrint(@"Encountered error replacing BaseSystem: %@", [errorInfo description]);
		[pool drain];
		exit(1);
	}
	
	[pool drain];
	return 0;
}