#include <Carbon/Carbon.r>

#define Reserved8   reserved, reserved, reserved, reserved, reserved, reserved, reserved, reserved
#define Reserved12  Reserved8, reserved, reserved, reserved, reserved
#define Reserved13  Reserved12, reserved
#define dp_none__   noParams, "", directParamOptional, singleItem, notEnumerated, Reserved13
#define reply_none__   noReply, "", replyOptional, singleItem, notEnumerated, Reserved13
#define synonym_verb__ reply_none__, dp_none__, { }
#define plural__    "", {"", kAESpecialClassProperties, cType, "", reserved, singleItem, notEnumerated, readOnly, Reserved8, noApostrophe, notFeminine, notMasculine, plural}, {}

resource 'aete' (0, "TerminalControl Terminology") {
	0x1,  // major version
	0x0,  // minor version
	english,
	roman,
	{
		"TerminalControl Suite",
		"Control Terminal.app",
		'TTpl',
		1,
		1,
		{
			/* Events */

			"apply title",
			"Apply title to a terminal specified with TTY",
			'TTpl', 'aplT',
			'bool',
			"true if successed to activate specified process.",
			replyRequired, singleItem, notEnumerated, Reserved13,
			'TEXT',
			"title of terminal",
			directParamRequired,
			singleItem, notEnumerated, Reserved13,
			{
				"for tty", 'fTTY', 'TEXT',
				"device name",
				optional,
				singleItem, notEnumerated, Reserved13,
				"to", 'tTab', 'obj ',
				"a reference to a terminal tab",
				optional,
				singleItem, notEnumerated, Reserved13
			},

			"title for tty",
			"get current custom for a terminal specifeid with TTY",
			'TTpl', 'getT',
			'TEXT',
			"custom title of a terminal",
			replyRequired, singleItem, notEnumerated, Reserved13,
			'TEXT',
			"TTY name",
			directParamRequired,
			singleItem, notEnumerated, Reserved13,
			{

			},

			"background color of term",
			"get current custom for a terminal",
			'TTpl', 'gBGc',
			'nmbr',
			"List of {Red, Green, Blue, Alpha}",
			replyRequired, listOfItems, notEnumerated, Reserved13,
			'****',
			"a TTY name or a reference to terminal tab.",
			directParamRequired,
			singleItem, notEnumerated, Reserved13,
			{

			},

			"apply background color",
			"Apply background color to a terminal specified with TTY",
			'TTpl', 'apBG',
			reply_none__,
			'nmbr',
			"List of {Red, Green, Blue, Alpha}",
			directParamRequired,
			listOfItems, notEnumerated, Reserved13,
			{
				"for tty", 'fTTY', 'TEXT',
				"device name",
				required,
				singleItem, notEnumerated, Reserved13
			},

			"activate terminal for directory",
			"activate tarminal tab or window for directory. Work after Mac OS 10.7.",
			'TTpl', 'acDr',
			'bool',
			"",
			replyRequired, singleItem, notEnumerated, Reserved13,
			'file',
			"a path to directory ",
			directParamRequired,
			singleItem, notEnumerated, Reserved13,
			{
				"allowing busy", 'awBy', 'bool',
				"If false, busy terminal will be skipped. The default value is false.",
				optional,
				singleItem, notEnumerated, Reserved13
			},

			"make tab",
			"Make a new tab",
			'TTpl', 'mkTb',
			'long',
			"index of new tab. If failed, zero will be returned.",
			replyRequired, singleItem, notEnumerated, Reserved13,
			'TEXT',
			"profile name",
			directParamOptional,
			singleItem, notEnumerated, Reserved13,
			{
				"in", 'kfil', 'obj ',
				"a reference to a window.",
				optional,
				singleItem, notEnumerated, Reserved13
			},

			"TerminalControl version",
			"get version number of TerminalControl",
			'TTpl', 'Vers',
			'TEXT',
			"version number",
			replyRequired, singleItem, notEnumerated, Reserved13,
			dp_none__,
			{

			}
		},
		{
			/* Classes */

		},
		{
			/* Comparisons */
		},
		{
			/* Enumerations */
		}
	}
};
