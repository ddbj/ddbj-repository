use magnus::{class, define_module, function, Error, ExceptionClass, Module, RClass, RModule};
use noodles_gff::{Directive, Line, Reader};

fn parse(input: String) -> Result<(), Error> {
    let mut reader = Reader::new(input.as_bytes());

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

    Ok(())
}
