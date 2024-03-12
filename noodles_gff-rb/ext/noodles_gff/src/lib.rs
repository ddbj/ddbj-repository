use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::PathBuf;

use magnus::{exception, function, Error, Ruby};
use noodles_gff::{Directive, Line, Reader};

fn parse(input: String) -> Result<(), Error> {
    let reader = Reader::new(input.as_bytes());

    read_lines(reader)
}

fn parse_from_file(path: PathBuf) -> Result<(), Error> {
    let reader = File::open(path)
        .map(BufReader::new)
        .map(Reader::new)
        .map_err(|e| Error::new(exception::runtime_error(), e.to_string()))?;

    read_lines(reader)
}

fn read_lines<T>(mut reader: Reader<T>) -> Result<(), Error>
where
    T: BufRead,
{
    for (i, line) in reader.lines().enumerate() {
        match line {
            Ok(Line::Directive(Directive::StartOfFasta)) => {
                return Ok(());
            }

            Ok(_) => (),

            Err(e) => {
                return Err(Error::new(exception::runtime_error(), format!("Line {}: {:?}", i + 1, e)));
            }
        }
    }

    Ok(())
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let gff = ruby.define_module("NoodlesGFF")?;

    gff.define_module_function("parse", function!(parse, 1))?;
    gff.define_module_function("parse_from_file", function!(parse_from_file, 1))?;

    Ok(())
}
