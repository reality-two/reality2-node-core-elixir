#[tokio::main]
async fn main(){
    use tomcat::*;
    if let Ok(res) = get("https://www.spacex.com").await{
        assert_eq!(200,res.status);
        assert_eq!(r#"{"content-type": "text/html; charset=utf-8", "vary": "Accept-Encoding", "date": "Sun, 09 Oct 2022 18:49:44 GMT", "connection": "keep-alive", "keep-alive": "timeout=5", "transfer-encoding": "chunked"}"#,format!("{:?}",res.headers));
        println!("{}",res.text);
        println!("{}",res.text_with_charset);
        println!("{}",res.url);
        println!("{}",res.remote_addr);
        println!("{:?}",res.version);
    }
    }
    pub fn look_ip(url: &str){
        use tomcat;
        use tokio::runtime::Runtime;
        let mut io_loop = Runtime::new().unwrap();
        
        let res = tomcat::get(url);
        let mut response = io_loop.block_on(res).unwrap();

        let addr = response.remote_addr.ip();
        print!("{:?}",addr);
    }