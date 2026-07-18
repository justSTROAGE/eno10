use clap::Parser;

#[derive(Parser, Debug)]
#[command(version, about = "FlagDrive", long_about = None)]
pub struct Args {
    #[arg(long = "database", short = 'd', default_value = "flagdrive.db")]
    pub database: String,

    #[arg(long = "addr", short = 'a', default_value = "0.0.0.0:4859")]
    pub addr: String,

    #[arg(long = "dist", default_value = "./dist")]
    pub dist: String,

    #[arg(long = "pg-host")]
    pub pg_host: Option<String>,

    #[arg(long = "pg-port")]
    pub pg_port: Option<u16>,

    #[arg(long = "pg-user")]
    pub pg_user: Option<String>,

    #[arg(long = "pg-password")]
    pub pg_password: Option<String>,

    #[arg(long = "pg-dbname")]
    pub pg_dbname: Option<String>,
}
