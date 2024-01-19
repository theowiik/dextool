/**
Date: 2015-2017, Joakim Brännström
License: MPL-2, Mozilla Public License 2.0
Author: Joakim Brännström (joakim.brannstrom@gmx.com)
*/
module application.app_main;

import logger = std.experimental.logger;

import colorlog : VerboseMode;
import dextool.type : ExitStatusType;

import application.cli_help;

version (unittest) {
    import unit_threaded : shouldEqual;
}

private enum CLICategoryStatus {
    Category,
    Help,
    Version,
    NoCategory,
    UnknownPlugin,
    PluginList,
}

private struct CLIResult {
    CLICategoryStatus status;
    string category;
    VerboseMode confLog;
    string[] args;
}

/** Parse the raw command line.
 */
auto parseMainCLI(const string[] args) {
    import std.algorithm : among, filter, findAmong;
    import std.array : array, empty;

    auto loglevel = findAmong(args, ["-d", "--debug"]).empty ? VerboseMode.info : VerboseMode.trace;
    // -d/--debug interferes with -h/--help/help and cli category therefore
    // remove
    string[] rem_args = args.dup.filter!(a => !a.among("-d", "--debug")).array();

    CLICategoryStatus state;

    if (rem_args.length <= 1) {
        state = CLICategoryStatus.NoCategory;
    } else if (rem_args.length >= 2 && rem_args[1].among("help", "-h", "--help")) {
        state = CLICategoryStatus.Help;
    } else if (rem_args.length >= 2 && rem_args[1].among("--version")) {
        state = CLICategoryStatus.Version;
    } else if (rem_args.length >= 2 && rem_args[1].among("--plugin-list")) {
        state = CLICategoryStatus.PluginList;
    }

    string category = rem_args.length >= 2 ? rem_args[1] : null;

    return CLIResult(state, category, loglevel);
}

version (unittest) {
    import std.algorithm : findAmong;
    import std.array : empty;

    // May seem unnecessary testing to test the CLI but bugs have been
    // introduced accidentally in parseMainCLI.
    // It is also easier to test "main CLI" here because it takes the least
    // setup and has no side effects.

    @("Should be no category")
    unittest {
        parseMainCLI(["dextool"]).status.shouldEqual(CLICategoryStatus.NoCategory);
    }

    @("Should flag that debug mode is to be activated")
    unittest {
        foreach (getValue; ["-d", "--debug"]) {
            auto result = parseMainCLI(["dextool", getValue]);
            result.confLog.shouldEqual(VerboseMode.trace);
        }
    }

    @("Should be the version category")
    unittest {
        auto result = parseMainCLI(["dextool", "--version"]);
        result.status.shouldEqual(CLICategoryStatus.Version);
    }

    @("Should be the help category")
    unittest {
        foreach (getValue; ["help", "-h", "--help"]) {
            auto result = parseMainCLI(["dextool", getValue]);
            result.status.shouldEqual(CLICategoryStatus.Help);
        }
    }
}

ExitStatusType runPlugin(CLIResult cli, string[] args) {
    import std.stdio : writeln;
    import application.plugin;

    auto exit_status = ExitStatusType.Errors;

    auto plugins = scanForExecutables.filterValidPluginsThisExecutable
        .toPlugins!executePluginForShortHelp;

    final switch (cli.status) with (CLICategoryStatus) {
    case Help:
        writeln(mainOptions, plugins.toShortHelp, commandGrouptHelp);
        exit_status = ExitStatusType.Ok;
        break;
    case Version:
        import dextool.utility : dextoolVersion;

        writeln("dextool version ", dextoolVersion);
        exit_status = ExitStatusType.Ok;
        break;
    case NoCategory:
        logger.error("No plugin specified");
        writeln("Available plugins:");
        writeln(plugins.toShortHelp);
        writeln("-h for further help");
        exit_status = ExitStatusType.Errors;
        break;
    case UnknownPlugin:
        logger.errorf("No such plugin found: '%s'", cli.category);
        writeln("Available plugins:");
        writeln(plugins.toShortHelp);
        writeln("-h for further help");
        exit_status = ExitStatusType.Errors;
        break;
    case PluginList:
        // intended to be used in automation. Akin to git "porcelain" commands"
        foreach (const ref p; plugins) {
            writeln(p.name);
        }
        exit_status = ExitStatusType.Ok;
        break;
    case Category:
        import std.algorithm : filter;
        import std.process : spawnProcess, wait;
        import std.range : takeOne;

        bool match_found;

        // dfmt off
        // find the first plugin matching the category
        foreach (p; plugins
                 .filter!(p => p.name == cli.category)
                 .takeOne) {
            auto pid = spawnProcess([cast(string) p.path] ~ (args.length > 2 ? args[2 .. $] : null));
            exit_status = wait(pid) == 0 ? ExitStatusType.Ok : ExitStatusType.Errors;
            match_found = true;
        }
        // dfmt on

        if (!match_found) {
            // print error message to user as if no category was found
            cli.status = CLICategoryStatus.UnknownPlugin;
            exit_status = runPlugin(cli, args);
        }

        break;
    }

    return exit_status;
}

int rmain(string[] args) nothrow {
    import std.exception : collectException;
    import colorlog : confLogger;

    auto exit_status = ExitStatusType.Errors;

    try {
        auto parsed = parseMainCLI(args);
        confLogger(parsed.confLog);

        exit_status = runPlugin(parsed, args);
        logger.errorf("exit status: %s", exit_status');
    } catch (Exception ex) {
        logger.trace(ex).collectException;
        exit_status = ExitStatusType.Errors;
    }

    if (exit_status != ExitStatusType.Ok) {
        logger.errorf("exiting...").collectException;
    }

    return cast(int) exit_status;
}
