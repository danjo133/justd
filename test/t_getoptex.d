#!/usr/bin/env rdmd

import std.stdio;
import std.getopt;

// private import std.contracts;
private import std.typetuple;
private import std.conv;

bool getoptEx(T...)(string helphdr, ref string[] args, T opts)
{
    assert(args.length,
            "Invalid arguments string passed: program name missing");

    string helpMsg = GetoptHelp(opts); // extract all help strings

    bool helpPrinted = false; // state tells if called with "--help"

    void printHelp()
    {
        writeln("\n", helphdr, "\n", helpMsg,
                "--help", "\n\tproduce help message");
        helpPrinted = true;
    }

    getopt(args, GetoptEx!(opts), "help", &printHelp);

    return helpPrinted;
}

private template GetoptEx(TList...)
{
    static if (TList.length)
        {
            static if (is(typeof(TList[0]) : config))
                {
                    // it's a configuration flag, lets move on
                    alias TypeTuple!(TList[0],GetoptEx!(TList[1 .. $])) GetoptEx;
                }
            else
                {
                    // it's an option string, eat help string
                    alias TypeTuple!(TList[0],TList[2],GetoptEx!(TList[3 .. $]))
                        GetoptEx;
                }
        }
    else
        {
            alias TList GetoptEx;
        }
}

private string GetoptHelp(T...)(T opts)
{
    static if (opts.length)
        {
            static if (is(typeof(opts[0]) : config))
                {
                    // it's a configuration flag, skip it
                    return GetoptHelp(opts[1 .. $]);
                }
            else
                {
                    // it's an option string
                    string option  = to!(string)(opts[0]);
                    string help    = to!(string)(opts[1]);

                    return( "--"~option~"\n"~help~"\n"~GetoptHelp(opts[3 .. $]) );
                }
        }
    else
        {
            return to!(string)("\n");
        }
}

void main(string[] args)
{
    string inputFile, outputFile;

    bool helpPrinted = getoptEx(
        "Test program to demonstrate getoptEx\n"~
        "written by Igor Lesik on Feb 2010\n"~
        "Usage: test1 { --switch }\n",
        args,
        std.getopt.config.caseInsensitive,
        "input",
        "\tinput file name,\n"~
        "\tmust be html file",
        &inputFile,
        "output",
        "\toutput file name",
        &outputFile,
        "author",
        "\tprint name of\n"~
        "\tthe author",
        delegate() {writeln("Igor Lesik");}
        );

    if (helpPrinted)
        return;

    writeln("Input file name:", inputFile);
    writeln("Output file name:", outputFile);
}
