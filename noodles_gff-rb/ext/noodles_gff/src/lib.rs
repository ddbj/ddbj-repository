use magnus::{class, define_module, function, Error, ExceptionClass, Module, RClass, RModule};
use noodles_gff::{self as gff};

fn parse(input: String) -> Result<(), Error> {
    let mut reader = gff::Reader::new(input.as_bytes());

    for (i, record) in reader.record_bufs().enumerate() {
        match record {
            Ok(_) => {},

            Err(e) => {
                let gff = class::object().const_get::<_, RModule>("NoodlesGFF")?;
                let error = gff.const_get::<_, ExceptionClass>("Error")?;
                let msg = format!("Line {}: {:?}", i + 1, e);

                return Err(Error::new(error, msg));
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
