use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::PathBuf;

use magnus::{class, define_module, exception, function, Error, ExceptionClass, Module, RClass, RModule};
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
                let gff = class::object().const_get::<_, RModule>("NoodlesGFF")?;
                let error = gff.const_get::<_, ExceptionClass>("Error")?;

                return Err(Error::new(error, format!("Line {}: {:?}", i + 1, e)));
            }
        }
    }

    Ok(())
}

#[magnus::init]
fn init() -> Result<(), Error> {
    let gff = define_module("NoodlesGFF")?;

    gff.define_class("Error", class::object().const_get::<_, RClass>("StandardError")?)?;

    gff.define_module_function("parse", function!(parse, 1))?;
    gff.define_module_function("parse_from_file", function!(parse_from_file, 1))?;

    Ok(())
}
