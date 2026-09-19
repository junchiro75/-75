//+------------------------------------------------------------------+
//| XAU_M10_BB_LIVE_004_FINAL.mq5                                   |
//| LIVE004 FINAL: research Virtual-MAX1 + separate real order state |
//| BB -> +0.95R -> extreme -> 0.10R pullback -> countertrend        |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

input double Lots=0.01;
input double ExtensionR=0.95;
input double PullbackR=0.10;
input double StopR=2.00;
input double TP1R=0.50;
input double LockR=0.25;
input double TP2R=0.90;
input int MaxExtensionHours=72;
input int MaxPullbackHours=72;
input int MaxVirtualExitHours=168;
input ulong MagicNumber=95011001;
input bool EnableLiveOrders=false;

CTrade trade;
int h20=INVALID_HANDLE,h4=INVALID_HANDLE;
datetime lastbar=0;

struct Setup{
 datetime sig,sigclose,extExpire,pbExpire;
 int sigdir;
 double R,C,extreme;
 bool extended;
};
Setup S[];

// Research virtual position. It determines WHICH triggers are accepted.
// Its 30/70 economics are independent of the broker's 0.01-lot mechanics.
bool vActive=false;
int vDir=0,vPhase=0;
double vR=0,vEntry=0,vSL=0,vTP1=0,vLock=0,vTP2=0;
datetime vEntryTime=0;
ulong vSeq=0;

void DelS(int i){
 int n=ArraySize(S);
 for(int j=i;j<n-1;j++)S[j]=S[j+1];
 ArrayResize(S,n-1);
}
double N(double p){return NormalizeDouble(p,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));}

bool Hedging(){
 return (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
}
int OwnPositions(){
 int c=0;
 for(int i=PositionsTotal()-1;i>=0;i--){
  ulong tk=PositionGetTicket(i);
  if(tk && PositionSelectByTicket(tk) &&
     PositionGetString(POSITION_SYMBOL)==_Symbol &&
     (ulong)PositionGetInteger(POSITION_MAGIC)==MagicNumber)c++;
 }
 return c;
}

void DetectSignal(){
 datetime cur=iTime(_Symbol,PERIOD_M10,0);
 if(cur==0||cur==lastbar)return; lastbar=cur;
 datetime st=iTime(_Symbol,PERIOD_M10,1);
 double o=iOpen(_Symbol,PERIOD_M10,1),h=iHigh(_Symbol,PERIOD_M10,1),
        l=iLow(_Symbol,PERIOD_M10,1),c=iClose(_Symbol,PERIOD_M10,1);
 double u20[1],lo20[1],u4[1],lo4[1];
 if(CopyBuffer(h20,1,1,1,u20)!=1||CopyBuffer(h20,2,1,1,lo20)!=1||
    CopyBuffer(h4,1,1,1,u4)!=1||CopyBuffer(h4,2,1,1,lo4)!=1)return;
 bool bull=c>o&&h>=u20[0]&&h>=u4[0];
 bool bear=c<o&&l<=lo20[0]&&l<=lo4[0];
 if(!bull&&!bear)return;
 double R=MathAbs(c-o); if(R<=0)return;
 int n=ArraySize(S);ArrayResize(S,n+1);
 S[n].sig=st;S[n].sigclose=st+600;
 S[n].extExpire=st+600+MaxExtensionHours*3600;S[n].pbExpire=0;
 S[n].sigdir=bull?1:-1;S[n].R=R;S[n].C=c;S[n].extreme=c;S[n].extended=false;
}

void StartVirtual(int dir,double R,double entry,datetime now){
 vActive=true;vDir=dir;vPhase=1;vR=R;vEntry=entry;vEntryTime=now;vSeq++;
 vSL=entry-dir*StopR*R;
 vTP1=entry+dir*TP1R*R;
 vLock=entry+dir*LockR*R;
 vTP2=entry+dir*TP2R*R;
 Print("LIVE004 FINAL VIRTUAL ACCEPT #",vSeq," ",dir==1?"BUY":"SELL",
       " entry=",DoubleToString(entry,_Digits)," R=",DoubleToString(R,_Digits));
}

void ManageVirtual(MqlTick &t){
 if(!vActive)return;
 datetime now=(datetime)(t.time_msc/1000);
 if(now<=vEntryTime)return;
 double px=vDir==1?t.bid:t.ask;

 if(vPhase==1){
  bool sl=vDir==1?px<=vSL:px>=vSL;
  bool t1=vDir==1?px>=vTP1:px<=vTP1;
  if(sl){Print("VIRTUAL EXIT SL #",vSeq);vActive=false;return;}
  if(t1){vPhase=2;return;}
 }else{
  bool tp=vDir==1?px>=vTP2:px<=vTP2;
  bool lk=vDir==1?px<=vLock:px>=vLock;
  if(tp){Print("VIRTUAL EXIT TP #",vSeq);vActive=false;return;}
  if(lk){Print("VIRTUAL EXIT LOCK #",vSeq);vActive=false;return;}
 }
 if(now>vEntryTime+MaxVirtualExitHours*3600){
  Print("VIRTUAL EXIT TIMEOUT #",vSeq);vActive=false;
 }
}

bool SendReal(int dir,double R,MqlTick &t){
 double entry=dir==1?t.ask:t.bid;
 double sl=entry-dir*StopR*R;
 double tp=entry+dir*TP2R*R;

 if(!EnableLiveOrders){
  Print("LIVE004 FINAL DRY: real order not sent.");
  return true;
 }
 if(!Hedging()){
  Print("LIVE004 FINAL BLOCKED: HEDGING account required for side-by-side 003/004.");
  return false;
 }
 if(OwnPositions()>0){
  // This should normally not occur. Never stack another LIVE004 real position.
  Print("LIVE004 FINAL SAFETY BLOCK: own real position still open.");
  return false;
 }
 trade.SetExpertMagicNumber(MagicNumber);
 trade.SetTypeFillingBySymbol(_Symbol);
 trade.SetDeviationInPoints(30);
 bool ok=dir==1 ? trade.Buy(Lots,_Symbol,0,N(sl),N(tp),"LIVE004_FINAL")
                : trade.Sell(Lots,_Symbol,0,N(sl),N(tp),"LIVE004_FINAL");
 if(!ok)Print("LIVE004 FINAL order failed: ",trade.ResultRetcode()," ",trade.ResultRetcodeDescription());
 return ok;
}

void ManageSetups(MqlTick &t){
 datetime now=(datetime)(t.time_msc/1000);
 for(int i=ArraySize(S)-1;i>=0;i--){
  if(now<=S[i].sigclose)continue;
  double px=S[i].sigdir==1?t.bid:t.ask;

  if(!S[i].extended){
   if(now>S[i].extExpire){DelS(i);continue;}
   double target=S[i].C+S[i].sigdir*ExtensionR*S[i].R;
   bool hit=S[i].sigdir==1?px>=target:px<=target;
   if(hit){
    S[i].extended=true;S[i].extreme=px;
    S[i].pbExpire=now+MaxPullbackHours*3600;
   }
   continue;
  }
  if(now>S[i].pbExpire){DelS(i);continue;}

  if(S[i].sigdir==1&&px>S[i].extreme)S[i].extreme=px;
  if(S[i].sigdir==-1&&px<S[i].extreme)S[i].extreme=px;
  double trigger=S[i].extreme-S[i].sigdir*PullbackR*S[i].R;
  bool rev=S[i].sigdir==1?px<=trigger:px>=trigger;
  if(!rev)continue;

  // Frozen research MAX1 rule: a trigger occurring while the VIRTUAL
  // research position is alive is rejected forever.
  if(vActive){
   Print("LIVE004 FINAL REJECT_MAX1 signal=",TimeToString(S[i].sig));
   DelS(i);continue;
  }

  int dir=-S[i].sigdir;
  double virtualEntry=dir==1?t.ask:t.bid;
  StartVirtual(dir,S[i].R,virtualEntry,now);

  // The accepted research trigger may send one real order.
  // If the broker rejects it, virtual research state remains active:
  // we do NOT substitute a later trigger and corrupt the tested sequence.
  SendReal(dir,S[i].R,t);
  DelS(i);
 }
}

bool StopsOK(double sl){
 MqlTick t;if(!SymbolInfoTick(_Symbol,t))return false;
 double md=MathMax((int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
                   (int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*_Point;
 if(sl<t.bid)return t.bid-sl>=md;
 return sl-t.ask>=md;
}
bool ModifyOwn(ulong ticket,double sl,double tp){
 if(!PositionSelectByTicket(ticket))return false;
 if(PositionGetString(POSITION_SYMBOL)!=_Symbol||
    (ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)return false;
 if(!StopsOK(sl))return false;
 trade.SetExpertMagicNumber(MagicNumber);
 return trade.PositionModify(ticket,N(sl),N(tp));
}

void ManageReal(MqlTick &t){
 for(int i=PositionsTotal()-1;i>=0;i--){
  ulong ticket=PositionGetTicket(i);
  if(!ticket||!PositionSelectByTicket(ticket))continue;
  if(PositionGetString(POSITION_SYMBOL)!=_Symbol||
     (ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber)continue;

  int dir=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
  double open=PositionGetDouble(POSITION_PRICE_OPEN);
  double sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
  double vol=PositionGetDouble(POSITION_VOLUME);
  bool protectedSL=dir==1?sl>=open:(sl>0&&sl<=open);

  double R=0;
  if(protectedSL&&tp>0)R=MathAbs(tp-open)/TP2R;
  else if(sl>0)R=MathAbs(open-sl)/StopR;
  if(R<=0)continue;

  double px=dir==1?t.bid:t.ask;
  double level=open+dir*TP1R*R;
  bool reached=dir==1?px>=level:px<=level;
  if(!reached||protectedSL)continue;

  double lock=open+dir*LockR*R;
  double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
  double minv=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
  double part=MathFloor((vol*0.30)/step+1e-9)*step;
  part=NormalizeDouble(part,2);

  if(part>=minv&&(vol-part)>=minv){
   trade.SetExpertMagicNumber(MagicNumber);
   if(trade.PositionClosePartial(ticket,part)){
    ModifyOwn(ticket,lock,tp);
   }else{
    Print("LIVE004 FINAL partial failed; protecting whole position.");
    ModifyOwn(ticket,lock,tp);
   }
  }else{
   // 0.01-lot fallback: no impossible 0.003 close.
   // Protect the whole live position at +0.25R, runner stays +0.9R.
   ModifyOwn(ticket,lock,tp);
  }
 }
}

int OnInit(){
 h20=iBands(_Symbol,PERIOD_M10,20,0,2.0,PRICE_CLOSE);
 h4=iBands(_Symbol,PERIOD_M10,4,0,4.0,PRICE_OPEN);
 if(h20==INVALID_HANDLE||h4==INVALID_HANDLE)return INIT_FAILED;
 trade.SetExpertMagicNumber(MagicNumber);

 if(EnableLiveOrders&&!Hedging()){
  Print("LIVE004 FINAL INIT FAILED: HEDGING account required.");
  return INIT_FAILED;
 }
 Print("LIVE004 FINAL initialized | Virtual MAX1 ON | Magic=",MagicNumber,
       " | Lots=",DoubleToString(Lots,2),
       " | orders=",EnableLiveOrders?"ENABLED":"DRY");
 return INIT_SUCCEEDED;
}

void OnTick(){
 MqlTick t;if(!SymbolInfoTick(_Symbol,t))return;
 DetectSignal();

 // IMPORTANT ordering matches the MAX1 diagnostic:
 // existing virtual position is resolved first; then same-tick triggers
 // may be accepted if the virtual position has just closed.
 ManageVirtual(t);
 ManageSetups(t);

 if(EnableLiveOrders)ManageReal(t);
}

void OnDeinit(const int reason){
 if(h20!=INVALID_HANDLE)IndicatorRelease(h20);
 if(h4!=INVALID_HANDLE)IndicatorRelease(h4);
}
//+------------------------------------------------------------------+
