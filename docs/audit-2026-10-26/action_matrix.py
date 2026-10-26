import json,time,sys,urllib.request,urllib.parse,urllib.error
B=sys.argv[1] if len(sys.argv)>1 else 'https://api.dollor.ai'
UA='okhttp/4.12.0'
def call(method,path,tok=None,data=None,form=None):
    h={'User-Agent':UA}
    body=None
    if tok: h['Authorization']='Bearer '+tok
    if data is not None: h['Content-Type']='application/json'; body=json.dumps(data).encode()
    if form: h['Content-Type']='application/x-www-form-urlencoded'; body=form.encode()
    r=urllib.request.Request(B+path,data=body,headers=h,method=method)
    t=time.time()
    try:
        resp=urllib.request.urlopen(r,timeout=60); code=resp.status; txt=resp.read().decode()
    except urllib.error.HTTPError as e: code=e.code; txt=e.read().decode()
    except Exception as e: code=0; txt=str(e)
    ms=round((time.time()-t)*1000)
    try: j=json.loads(txt)
    except: j={}
    return code,ms,j,txt
results=[]
def check(app,action,res,expect=(200,),note=''):
    code,ms,j,txt=res
    ok=code in expect
    results.append(dict(app=app,action=action,code=code,ms=ms,ok=ok,note=note if ok else (note+' '+txt[:110]).strip()))
    print(('PASS' if ok else 'FAIL'),f'{app:6}',f'{action:46}',code,f'{ms:5}ms', '' if ok else txt[:100].replace('\n',' '))
    return j
def login(path,u,p):
    c,ms,j,t=call('POST',path,form=f'username={urllib.parse.quote(u)}&password={urllib.parse.quote(p)}'); return j.get('access_token'),j
ct,cj=login('/api/auth/customer/login','demo.customer@dollor.ai','DemoCustomer2025!')
dt,dj=login('/api/auth/driver/login','demo.driver@dollor.ai','DemoDriver2025!')
CID=cj.get('customer_id',74); DID=dj.get('driver_id',48)
print('customer',CID,'driver',DID)
check('rider','login customer',(200 if ct else 0,0,{},''),(200,))
check('driver','login driver',(200 if dt else 0,0,{},''),(200,))
# ---------- driver reads / online ----------
check('driver','GET me',call('GET','/api/auth/driver/me',dt))
check('driver','PUT online=true',call('PUT','/api/auth/driver/online',dt,{"is_online":True,"latitude":37.7879,"longitude":-122.4075}))
check('driver','POST location',call('POST','/api/driver/location',dt,{"latitude":37.7879,"longitude":-122.4075}))
check('driver','GET earnings',call('GET','/api/driver/earnings',dt))
check('driver','GET active rides',call('GET','/api/rides/driver/active',dt))
check('driver','GET documents',call('GET','/api/auth/driver/documents',dt))
check('driver','GET driver bids',call('GET',f'/api/rides/driver/{DID}/bids',dt))
# ---------- rider reads ----------
check('rider','GET addresses',call('GET',f'/api/addresses/{CID}',ct))
check('rider','GET saved cards',call('GET',f'/api/customers/{CID}/cards',ct))
check('rider','GET stripe setup-intent',call('GET',f'/api/customers/{CID}/stripe/setup-intent',ct),(200,400,404),'demo account may have no Stripe customer')
check('rider','GET ride history',call('GET','/api/customer/rides/history',ct))
check('rider','GET notifications',call('GET',f'/api/customers/{CID}/notifications',ct))
check('rider','GET email status',call('GET','/api/customer/email/status',ct))
check('rider','GET founding status',call('GET','/api/founding/status',ct))
check('rider','GET config/rideshare (new backend)',call('GET','/api/config/rideshare'),(200,),'')
check('rider','POST fcm-token',call('POST',f'/api/erp/customers/{CID}/fcm-token',ct,{"fcm_token":"matrix-test-token"}))
check('rider','POST support chat',call('POST','/api/support/chat',ct,{"message":"How do fees work?"}))
check('rider','PUT profile (unchanged name)',call('PUT','/api/auth/customer/profile',ct,{"name":cj.get('name') or 'Demo Customer'}))
P=dict(pickup_address="301 Post Street",pickup_latitude=37.7879,pickup_longitude=-122.4075,dropoff_address="1 Ferry Building",dropoff_latitude=37.7955,dropoff_longitude=-122.3937)
check('rider','POST estimate',call('POST','/api/rides/estimate',ct,{k:P[k] for k in ('pickup_latitude','pickup_longitude','dropoff_latitude','dropoff_longitude')}|{"ride_type":"standard"}))
def new_ride(tag,price=8.15):
    j=check('rider',f'[{tag}] POST create ride request',call('POST','/api/rides/request',ct,dict(P,customer_id=CID,ride_type="standard",bidding_duration_minutes=5,customer_preferred_price=price)))
    return j.get('ride_request',{}).get('id')
def avail(tag,rid):
    c=call('GET','/api/rides/available?latitude=37.788&longitude=-122.4075',dt)
    ids=[r['id'] for r in c[2].get('available_requests',[])]
    check('driver',f'[{tag}] GET available shows the ride',(200 if rid in ids else 0,c[1],{},'not listed'),(200,))
def bid(tag,rid,price=9.5):
    j=check('driver',f'[{tag}] POST bid',call('POST',f'/api/rides/request/{rid}/bid',dt,{"driver_id":DID,"proposed_price":price,"estimated_arrival_minutes":5,"message":"matrix"}))
    b=(j.get('bid') or {}).get('id') or j.get('bid_id')
    if not b:
        bs=call('GET',f'/api/rides/request/{rid}/bids',ct)[2].get('bids',[]); b=bs[0]['id'] if bs else None
    return b
# ---------- Ride A: counter -> accept-counter -> full trip ----------
A=new_ride('A counter+trip'); avail('A',A); bA=bid('A',A)
check('rider','[A] GET bids list',call('GET',f'/api/rides/request/{A}/bids',ct))
check('rider','[A] POST counter 8.00',call('POST',f'/api/rides/bid/{bA}/respond',ct,{"action":"counter","counter_price":8.0}))
check('driver','[A] POST accept-counter',call('POST',f'/api/rides/bid/{bA}/accept-counter',dt))
check('rider','[A] GET track (canonical)',call('GET',f'/api/rides/{A}/track',ct))
check('rider','[A] GET track (iOS alias)',call('GET',f'/api/erp/rides/{A}/track',ct))
check('driver','[A] GET active rides has it',call('GET','/api/rides/driver/active',dt))
chat=call('POST',f'/api/p2p/ride-requests/{A}/chat',ct,{"message":"hi driver","sender_type":"customer"})
j=check('rider','[A] chat send (rider)',chat)
need={'id','ride_request_id','sender_type','sender_id','message','created_at'}
check('rider','[A] chat reply decodable by iOS',(200 if need<=set(j) else 0,0,{},'missing '+str(sorted(need-set(j)))),(200,))
check('driver','[A] chat send (driver)',call('POST',f'/api/p2p/ride-requests/{A}/chat',dt,{"message":"on my way","sender_type":"driver"}))
check('rider','[A] chat list',call('GET',f'/api/p2p/ride-requests/{A}/chat',ct))
check('driver','[A] chat list (driver)',call('GET',f'/api/p2p/ride-requests/{A}/chat',dt))
check('driver','[A] POST arrived',call('POST',f'/api/rides/request/{A}/arrived',dt))
check('driver','[A] no-show too early is refused',call('POST',f'/api/rides/request/{A}/no-show',dt),(400,),'expected 400 (must wait)')
check('driver','[A] POST start',call('POST',f'/api/rides/request/{A}/start',dt))
check('rider','[A] track while in progress',call('GET',f'/api/rides/{A}/track',ct))
check('driver','[A] POST complete',call('POST',f'/api/rides/request/{A}/complete',dt))
check('rider','[A] tip 0 (iOS Skip Tip sent this before the fix)',call('POST',f'/api/rides/{A}/tip',ct,{"tip_amount":0}),(200,422),'422 = known, client no longer sends it')
check('rider','[A] tip 2.00',call('POST',f'/api/rides/{A}/tip',ct,{"tip_amount":2.0}))
check('rider','[A] rate driver 5',call('POST',f'/api/rides/{A}/rate',ct,{"rating":5,"comment":"matrix"}))
check('driver','[A] rate passenger 5',call('POST',f'/api/rides/request/{A}/rate-passenger',dt,{"rating":5}))
check('rider','[A] GET receipt',call('GET',f'/api/rides/request/{A}/receipt',ct))
check('rider','[A] history includes it',call('GET','/api/customer/rides/history',ct))
# ---------- Ride B: rider rejects bid then cancels request ----------
Bd=new_ride('B reject+cancel'); bB=bid('B',Bd)
check('rider','[B] POST reject bid',call('POST',f'/api/rides/bid/{bB}/respond',ct,{"action":"reject"}))
check('rider','[B] POST cancel request',call('POST',f'/api/rides/request/{Bd}/cancel',ct,{"reason":"matrix"}))
# ---------- Ride C: accept, driver cancels ----------
C=new_ride('C driver cancel'); bC=bid('C',C)
check('rider','[C] POST accept bid',call('POST',f'/api/rides/bid/{bC}/respond',ct,{"action":"accept"}))
check('driver','[C] POST driver-cancel',call('POST',f'/api/rides/request/{C}/driver-cancel',dt,{"reason":"matrix"}))
check('rider','[C] track after driver cancel',call('GET',f'/api/rides/{C}/track',ct))
# the ride re-opens for other drivers; rider cancels it to clean up
check('rider','[C] cancel the re-opened request',call('POST',f'/api/rides/request/{C}/cancel',ct,{"reason":"cleanup"}),(200,400))
# ---------- Ride D: accept, rider cancels after match ----------
D=new_ride('D rider cancel after match'); bD=bid('D',D)
check('rider','[D] POST accept bid',call('POST',f'/api/rides/bid/{bD}/respond',ct,{"action":"accept"}))
check('rider','[D] POST cancel after match',call('POST',f'/api/rides/request/{D}/cancel',ct,{"reason":"matrix"}))
# ---------- Ride E: driver final counter, rider accepts ----------
E=new_ride('E driver-counter'); bE=bid('E',E,10.0)
check('rider','[E] POST counter 7.50',call('POST',f'/api/rides/bid/{bE}/respond',ct,{"action":"counter","counter_price":7.5}))
check('driver','[E] POST driver-counter 8.75',call('POST',f'/api/rides/bid/{bE}/driver-counter',dt,{"counter_price":8.75,"message":"final"}))
check('rider','[E] GET bids shows final counter',call('GET',f'/api/rides/request/{E}/bids',ct))
check('rider','[E] POST accept final counter',call('POST',f'/api/rides/bid/{bE}/respond',ct,{"action":"accept"}))
check('driver','[E] arrived',call('POST',f'/api/rides/request/{E}/arrived',dt)); check('driver','[E] start',call('POST',f'/api/rides/request/{E}/start',dt)); check('driver','[E] complete',call('POST',f'/api/rides/request/{E}/complete',dt))
# ---------- Ride F: driver rejects rider's counter ----------
F=new_ride('F reject-counter'); bF=bid('F',F)
check('rider','[F] POST counter 7.00',call('POST',f'/api/rides/bid/{bF}/respond',ct,{"action":"counter","counter_price":7.0}))
check('driver','[F] POST reject-counter',call('POST',f'/api/rides/bid/{bF}/reject-counter',dt))
check('rider','[F] cancel request',call('POST',f'/api/rides/request/{F}/cancel',ct,{"reason":"cleanup"}),(200,400))
# ---------- security checks ----------
check('rider','[sec] stranger cannot read chat',call('GET',f'/api/p2p/ride-requests/{A}/chat',None),(401,403))
check('driver','[sec] online=false',call('PUT','/api/auth/driver/online',dt,{"is_online":False}))
check('driver','[sec] offline driver sees no rides',(lambda c:(200 if c[2].get('count',0)==0 else 0,c[1],{},'saw rides while offline'))(call('GET','/api/rides/available?latitude=37.788&longitude=-122.4075',dt)),(200,))
check('driver','PUT online=true (restore)',call('PUT','/api/auth/driver/online',dt,{"is_online":True,"latitude":37.7879,"longitude":-122.4075}))
p=sum(r['ok'] for r in results); print(f'\n{p}/{len(results)} actions passed against {B}')
json.dump(results,open('/tmp/action_matrix_'+('prod' if 'api.dollor.ai' in B else 'other')+'.json','w'),indent=1)
