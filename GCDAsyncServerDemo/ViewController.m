//
//  ViewController.m
//  GCDAsyncServerDemo
//
//  Created by Marshal on 2021/5/24.
//

#import "ViewController.h"
#import <CocoaAsyncSocket/GCDAsyncSocket.h>

@interface ViewController ()<GCDAsyncSocketDelegate>

@property (nonatomic, strong) GCDAsyncSocket *socket; //服务端的socket对象
@property (nonatomic, strong) NSMutableArray *clientSockets; //连接的客户端socket对象集合

@property (weak, nonatomic) IBOutlet UITextField *tfSendMessage;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self initServerSocket];
}

- (void)initServerSocket {
    self.clientSockets = [NSMutableArray arrayWithCapacity:10];
    
    self.socket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)];
    
    NSError *error;
    //开启接收服务器
    [self.socket acceptOnPort:8040 error:&error];
    if (error) {
        NSLog(@"服务器开启失败:%@",error.localizedDescription);
    }else {
        NSLog(@"服务器socket开启成功");
    }
}

//客户端已经连接到当前服务器
- (void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket {
    [self.clientSockets addObject:newSocket];
    
    [newSocket readDataWithTimeout:-1 tag:10010]; //读取客户端发送过来的消息
}

//socket断开连接
- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
    NSLog(@"socket断开连接: %@", err.localizedDescription);
}

//接收到客户端的数据
//消息结构 数据长度 + 数据类型 + 数据，需要解决粘包和拆包的问题
- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    //这里可以打印数据，数据来自多个socket，每个socket都需要对应一个MutableData来接收数据，避免数据混乱，这里只处理一个客户端的情况，实际可以设置新的数据结构来处理这个问题{host: {socket, MutableData}}，这里的就不多介绍了
    
    NSLog(@"-------------接收到了数据:%ld-----------", tag);
    if (data.length < 1) return;
    
    unsigned long totolLength = data.length;
    unsigned long currentLength = 0;
    //do while解决粘包问题，在里面进行拆包
    do {
        unsigned long length;
        unsigned int type;
        [data getBytes:&length range:NSMakeRange(currentLength, 8)];
        [data getBytes:&type range:NSMakeRange(currentLength + 8, 4)];
        //获取实际数据
        NSData *contentData = [data subdataWithRange:NSMakeRange(currentLength + 12, length-12)];
        
        if (type == 1) {
            //文字
            NSString *content = [[NSString alloc] initWithData:contentData encoding:NSUTF8StringEncoding];
            NSLog(@"接收的数据为:%@", content);
        }else if (type == 2) {
            //图片
            [self showImageInfo:contentData];
        }else {
            NSLog(@"不支持的数据类型");
        }
        currentLength += length;
    } while (currentLength < totolLength);
   
    //读取完毕数据之后，缓存区断开，需要重新监听
    [sock readDataWithTimeout:-1 tag:10010];
}

//消息发送成功
- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {
    NSLog(@"消息发送成功:%ld", tag);
}

//断开连接
- (IBAction)onClickToDisconnect:(id)sender {
    [self.socket disconnect];
    self.socket = nil;
}

//发送消息，发送消息的过程中如论如何必须保证包有序的进行传输，即：传输A、B两个数据，由于数据比较大分为A1, A2，B1, B2,可能出现A1、A2B1B2的方式传输过来，因此会出现粘包拆包的过程，切记不能以A1B1、A2B2这种非顺序性传输，会加大处理难度
//消息结构 数据长度 + 数据类型 + 数据(自己也可以加上发送时间之类的，可以根据实际场景定制)
//如果一个数据较长(视频),可以分为几段传递，那么还需要将内容粘到一起，因此：数据总长度 + 数据长度 + 数据类型 + 数据;
//实际推荐视频、大图片走文件传输线路放到文件服务器，socket单个socket负责传输视频或者图片url即可，这样可以避免大文件信息堆积严重
- (IBAction)onClickToSend:(id)sender {
    NSMutableData *mData = [NSMutableData data];
    if (self.tfSendMessage.text.length > 0) {
        //给没个客户端发送一段数据
        const char *textStr = self.tfSendMessage.text.UTF8String;
        NSData *data = [NSData dataWithBytes:textStr length:strlen(textStr)];
        
        unsigned long dataLength = 8 + 4 + data.length;
        NSData *lenData = [NSData dataWithBytes:&dataLength length:8];
        [mData appendData:lenData];
        
        //文字类型
        unsigned int typeByte = 0x00000001;
        NSData *typeData = [NSData dataWithBytes:&typeByte length:4];
        [mData appendData:typeData];
        
        [mData appendData:data];
        NSLog(@"发送内容为：%@", self.tfSendMessage.text);
        self.tfSendMessage.text = @"";
    }else {
        //发送图片,其实实际上不一定在非要传递图片的，有的走的是http上传到文件服务器,然后利用返回的url在发送给对方
        NSData *imgData = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"cat" ofType:@"jpeg"]];
        
        //展示发送的图片4s
        [self showImageInfo:imgData];
        
        //发送图片
        unsigned long dataLength = 8 + 4 + imgData.length;
        NSData *lenData = [NSData dataWithBytes:&dataLength length:8];
        [mData appendData:lenData];
        
        //图片类型
        unsigned int typeByte = 0x00000002;
        NSData *typeData = [NSData dataWithBytes:&typeByte length:4];
        [mData appendData:typeData];
        
        [mData appendData:imgData];
    }
    //发送消息
    for (GCDAsyncSocket *cSocket in self.clientSockets) {
        [cSocket writeData:mData withTimeout:-1 tag:0];
    }
}

//展示发送的图片
- (void)showImageInfo:(NSData *)imgData {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIImageView *ivImage = [[UIImageView alloc] initWithImage:[UIImage imageWithData:imgData]];
        ivImage.frame = CGRectMake(20, 300, 300, 300);
        [self.view addSubview:ivImage];
        
        ivImage.transform = CGAffineTransformScale(CGAffineTransformIdentity, 0.1, 0.1);
        [UIView animateWithDuration:2 animations:^{
            ivImage.transform = CGAffineTransformScale(CGAffineTransformIdentity, 1, 1);
        } completion:^(BOOL finished) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [ivImage removeFromSuperview];
            });
        }];
    });
}



@end