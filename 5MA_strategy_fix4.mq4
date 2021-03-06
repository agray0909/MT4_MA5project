//+------------------------------------------------------------------+
//|                                            5MA_strategy_fix4.mq4 |
//|                        Copyright 2014, MetaQuotes Software Corp. |
//|                                              http://www.mql5.com |
//+------------------------------------------------------------------+

/*-------------------
筆記:
   追加平倉時間選擇功能
   對應使用者定義的period
   
11/17 note:
         可執行, 可能有潛在bug, must check! 
      continued: 
         策略部分盡可能改fucntion化, current time做成變數方便測試, period 1 min有問題?(finish), 有平倉當下買 隔天結的bug
11/18 note:
         period 1 min的問題 看起來history data有跳號的問題, 5min 15min由8月開始才有資料, 1min 9/3直接跳到9/29
11/19 note:
         追加使用者參數交易安全區間, 表示平倉時間往前的指定時間區間不執行交易, 貌似有較好的獲益
11/21 note:
         追加使用者參數停損止益, 有交易次數bug, 不過顯示出有意思的現象, 版本暫留
11/25 note:
         對應下載data只有1min, 修改period為1min; 需處理星期六日沒有data的問題

-------------------*/
#property copyright "Copyright 2014, MetaQuotes Software Corp."
#property link      "http://www.mql5.com"
#property version   "1.00"
#property strict

extern double TakeProfit=250.0; //止益點數
extern double StopLost= 400.0; //停損點數
extern double Lots=0.1; //預設手數
extern int coverType = 1; //平倉類型: 1為2200平倉,交易時間1700~2200; 2為0200平倉,交易時間1700~0200
extern int excuteSafeTime_hour = 0;//交易安全區間: 由平倉時間往前推n小時, 例如1表示平倉前一小時不交易, 目前此區間大於換日與執行區間會有bug
extern int dailyTradeLimit = 1;

int tickCount=0;
int total=0; //目前的交易單數
double openPrice_1600,openPrice_1630,minus_1630to1600,ma5open_1600;
//平倉與交易時間 array[0]為時, array[1]為分
int coverTime[2],excuteTime[4];

int excuteSafeTime[2];

int trend = 0; //本日走勢預測由1600~1630差價決定, 0表示無預測, 1漲勢, 2跌勢
bool flag_pBelowMA = false,flag_pAboveMA = false;
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
      //按使用者參數設置交易期間與平倉時間
      setCoverType(coverType);
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
      tickCount++; total  = OrdersTotal();
      bool inExcuteTime, inCoverTime;
      static int tradeCount = 0; //紀錄本日累計交易次數 平倉時間歸0
      
      //在16:30 做預測今日走勢strategy
      if(checkTime(16,30,16,30)){
         /*Print("in 1630 struct: ");
         Print("iOpen1 now: ",iOpen(Symbol(),1,0));
         Print("iOpen1 shift30: ", iOpen(Symbol(),1,30));
         Print("iOpen30 now: ",iOpen(Symbol(),30,0));
         Print("iOpen30 shift1: ", iOpen(Symbol(),30,1));
         Print("ima(5)30 shift1",iMA(Symbol(),30,5,1,0,1,0));
         Print("ima(150)1 shift30",iMA(Symbol(),1,150,30,0,1,0));
         */
         trend = predictTrend();                
      }
      
      //在指定的時間執行交易策略
      if(checkTime(excuteTime[0],excuteTime[1],excuteTime[2],excuteTime[3])){
         //檢查兩次checkTime 需要修改, 這寫法超過兩小時可能會有問題(e.g. 02-4 = -4)
         if(!checkTime(excuteTime[2]-excuteSafeTime_hour,excuteTime[3],excuteTime[2],excuteTime[3])){
            inExcuteTime = true;
            //trend==1 看多策略
            if(trend == 1){                 
               //價格在區間中曾經低於16點的MA線, 紀錄flag
               if(iOpen(Symbol(),0,0) < ma5open_1600)
                  flag_pBelowMA = true;            
               //flag below開啟過, 且現價大於MA1600, 且手邊無單, 且不超過本日限定交易次數, 則開啟交易
               if(flag_pBelowMA && iOpen(Symbol(),0,0) > ma5open_1600 && total<1 && tradeCount < dailyTradeLimit){
                  newBuyOrder_askprice(); tradeCount++;           
                  return; 
               }
            } 
            //trend==2 看空策略
            if(trend == 2){
               if(iOpen(Symbol(),0,0) > ma5open_1600)
                  flag_pAboveMA = true;  
               if(flag_pAboveMA && iOpen(Symbol(),0,0) < ma5open_1600 && total<1 && tradeCount < dailyTradeLimit){
                  newSellOrder_bidprice(); tradeCount++;        
                  return;  
               }
            }          
         }
      }
      //非指定的交易時間 且不是1600~1700 參數歸零
      else{
         if(!checkTime(16,0,17,0)){
            openPrice_1600 =0; openPrice_1630 = 0; minus_1630to1600=0; ma5open_1600 = 0; ma5open_1600=0;
            flag_pBelowMA = false; flag_pAboveMA = false;
            inExcuteTime=false;inCoverTime=false;
            trend = 0;
            tradeCount = 0;
         }
      }
      
      //在指定的時間平倉
      if(checkTime(coverTime[0],coverTime[1],coverTime[0],coverTime[1])){
         inCoverTime = true;
         coverOrder();
      }
      
      Comment("tickCount: ",tickCount,"\n\n",
         "----------執行期間參數-----------\n",
         "coverType: ",coverType,"\n"
         "交易時間: ",excuteTime[0],":",excuteTime[1],"~",excuteTime[2],":",excuteTime[3],"  現在為交易時間: ",inExcuteTime,"\n",
         "平倉時間: ",coverTime[0],":",coverTime[1],"  現在為平倉時間: ",inCoverTime,"\n\n",
         "----------買賣指標參數-----------\n",
         "1600開盤價: ",openPrice_1600,"  1630開盤價: ",openPrice_1630,"\n","1630to1600差價: ",minus_1630to1600,"\n",
         "本日走勢預測: ",(trend==0) ? " -- ": trend==1?"看多":"看空" ,"\n",
         "ma5open_1600: ",ma5open_1600,"  現開盤價:",iOpen(Symbol(),0,0),"\n\n",
         "----------低於/高於flag-----------\n",
         "flag_pBelowMA: ",flag_pBelowMA ,"  flag_pAboveMA: ",flag_pAboveMA,"\n",
         "本日交易次數: ",tradeCount
      );
  }
  
//+------------------------------------------------------------------+
//以下為function
//+------------------------------------------------------------------+


//檢查目前時間是否在指定區間, 24小時制, 接受開始結束時間同時
bool checkTime(int startHour, int startMinute, int endHour, int endMinute){
   bool inTime = false;
   double currentTime = Hour() + Minute()*0.01;
   double startTime = startHour + startMinute*0.01;
   double endTime = endHour + endMinute*0.01;
   
   //由開始結束hour大小來分是否跨天兩種類型, 例start:1800 end:2100; start:2200 end 0200
   if(startHour <= endHour){   
      if(currentTime >= startTime && currentTime <= endTime)
         inTime = true;
   }
   else{
      if(currentTime >= startTime || currentTime <= endTime)
         inTime = true;
   }
   return inTime;
}

//平倉, 挑出最近的買單/賣單, 直接市價平倉
void coverOrder(){
   if(total>0){
      //這邊我們只有一單 因此SELECT_BY_POS的array 0即是那張交易單
      OrderSelect(0, SELECT_BY_POS, MODE_TRADES);
      if(OrderType()==OP_BUY)
         OrderClose(OrderTicket(),OrderLots(),Bid,3,Violet);     
      if(OrderType()==OP_SELL)
         OrderClose(OrderTicket(),OrderLots(),Ask,3,Violet); 
   }
}

//由使用者參數決定平倉執行時間
void setCoverType(int coverType){
   //平倉類型為1, 2200平倉, 交易時間為1700~2200
   if(coverType==1){
      coverTime[0] = 22; coverTime[1] = 0;
      excuteTime[0] = 17; excuteTime[1] = 0; excuteTime[2] = 22; excuteTime[3] = 0;      
   }
   //平倉類型為2, 0200平倉, 交易時間為1700~0200
   if(coverType==2){
      coverTime[0] = 2; coverTime[1] = 0;
      excuteTime[0] = 17; excuteTime[1] = 0; excuteTime[2] = 2; excuteTime[3] = 0;
   }
}

//買單交易 以市場買價
bool newBuyOrder_askprice(){
   bool trade=false;
   double ticket;
   ticket=OrderSend(Symbol(),OP_BUY,Lots,Ask,3,(StopLost==0)? 0 : Bid-Point*StopLost,(TakeProfit==0)? 0 : Ask+TakeProfit*Point,"Leon 5 MA",12345,0,Green);
   if(ticket>0)
     {               
      if(OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES)){
         Print("BUY order opened : ",OrderOpenPrice());
         return(true);
       }
     }
   else{
      Print("Error opening BUY order : ",GetLastError()); 
   }
   return(trade);
}
//賣單交易 以市場賣價
bool newSellOrder_bidprice(){
   bool trade=false;
   double ticket;
   ticket=OrderSend(Symbol(),OP_SELL,Lots,Bid,3,(StopLost==0)? 0 : Ask+Point*StopLost,(TakeProfit==0)? 0 : Bid-TakeProfit*Point,"Leon 5 MA",12345,0,Green);
   if(ticket>0)
     {               
      if(OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES)){
         Print("SELL order opened : ",OrderOpenPrice());
         return(true);
       }
     }
   else{
      Print("Error opening SELL order : ",GetLastError()); 
   }
   return(trade);
}

//預測今日走勢策略
//16:30時 紀錄16:00與16:30的價差, 以及16往前2.5小時的開盤MA
int predictTrend(){   
   //取1600,1630兩根bar的開盤價 以此差價作為今日預測的基準; 11-25對應只有1min history改用period 1 min     
   openPrice_1630= iOpen(Symbol(),1,0); openPrice_1600 = iOpen(Symbol(),1,30);         
   minus_1630to1600 = openPrice_1630 - openPrice_1600;
   //注意此處是shift=1, 30timeframe就是16點的MA(5)
   ma5open_1600 = iMA(Symbol(),1,150,30,0,1,0);
   //ma5close_1530 = iMA(Symbol(),30,5,2,0,0,0);
   return((minus_1630to1600 > 0) ? 1:2);         
}