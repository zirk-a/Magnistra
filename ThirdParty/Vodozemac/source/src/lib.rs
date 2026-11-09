// Standalone reusable iOS5/ARMv7 FFI bridge to vodozemac 0.11.0.
// Offline by design. The calling app is responsible for Matrix network,
// secure pickle key management and atomic state persistence.
use core::ffi::c_void;
use std::{collections::BTreeMap, ptr, slice, str};
use vodozemac::{Curve25519PublicKey, olm::{Account, AccountPickle, OlmMessage, PreKeyMessage,
    Session, SessionConfig as OC, SessionPickle}, megolm::{GroupSession, GroupSessionPickle,
    InboundGroupSession, InboundGroupSessionPickle, MegolmMessage, SessionConfig as MC, SessionKey}};

const MAX: usize = 2*1024*1024;
const VERSION: u32 = 0x0003_0000;
const ACCOUNT: u32 = 1;
const OLM: u32 = 2;
const OUT_GROUP: u32 = 3;
const IN_GROUP: u32 = 4;

enum Item { Account(Account), Olm(Session), Out(GroupSession), In(InboundGroupSession) }
struct Opaque { item: Item }
fn boxed(item: Item) -> *mut c_void { Box::into_raw(Box::new(Opaque { item })) as *mut c_void }
unsafe fn as_item<'a>(handle: *mut c_void) -> Option<&'a mut Item> {
    if handle.is_null() { None } else { Some(&mut (*(handle as *mut Opaque)).item) }
}
unsafe fn in_bytes<'a>(p:*const u8, n:usize)->Option<&'a [u8]> {
    if n>MAX { return None; }
    if n==0 { return Some(&[]); }
    if p.is_null() {return None;}
    Some(slice::from_raw_parts(p,n))
}
unsafe fn in_str<'a>(p:*const u8,n:usize)->Option<&'a str> {
    str::from_utf8(in_bytes(p,n)?).ok()
}
unsafe fn key_32<'a>(p:*const u8,n:usize)->Option<&'a [u8;32]> {
    if n!=32 || p.is_null(){return None;}
    Some(&*(p as *const [u8;32]))
}
unsafe fn write(buf:&[u8],out:*mut u8,cap:usize)->isize {
    if buf.len()>MAX || out.is_null() || cap<buf.len() {return -1;}
    if !buf.is_empty(){ptr::copy_nonoverlapping(buf.as_ptr(),out,buf.len());}
    buf.len() as isize
}
unsafe fn text(s:&str,out:*mut u8,cap:usize)->isize {write(s.as_bytes(),out,cap)}

#[no_mangle] pub extern "C" fn vdz5_r3_abi_version()->u32 { VERSION }
#[no_mangle] pub unsafe extern "C" fn vdz5_r3_release(h:*mut c_void) {
    if !h.is_null(){ drop(Box::from_raw(h as *mut Opaque)); }
}
#[no_mangle] pub extern "C" fn vdz5_r3_account_new()->*mut c_void { boxed(Item::Account(Account::new())) }
#[no_mangle] pub unsafe extern "C" fn vdz5_r3_account_identity(h:*mut c_void,which:u32,out:*mut u8,cap:usize)->isize {
    match as_item(h) {
        Some(Item::Account(a))=>match which {
            1=>text(&a.ed25519_key().to_base64(),out,cap),
            2=>text(&a.curve25519_key().to_base64(),out,cap),
            _=>-1,
        },_=>-1
    }
}
#[no_mangle] pub unsafe extern "C" fn vdz5_r3_account_generate_otk(h:*mut c_void,n:u32)->i32 {
    if n==0 || n>100 {return -1;}
    match as_item(h) {Some(Item::Account(a))=>{a.generate_one_time_keys(n as usize);0},_=>-1}
}
#[no_mangle] pub unsafe extern "C" fn vdz5_r3_account_unpublished_otk_json(h:*mut c_void,out:*mut u8,cap:usize)->isize {
    match as_item(h){Some(Item::Account(a))=>{
        let map:BTreeMap<String,String>=a.one_time_keys().into_iter().map(|(k,v)|(k.to_base64(),v.to_base64())).collect();
        match serde_json::to_string(&map){Ok(s)=>text(&s,out,cap),Err(_)=>-1}
    },_=>-1}
}
#[no_mangle] pub unsafe extern "C" fn vdz5_r3_account_generate_fallback(h:*mut c_void)->i32 {
    match as_item(h){Some(Item::Account(a))=>{a.generate_fallback_key();0},_=>-1}
}
#[no_mangle] pub unsafe extern "C" fn vdz5_r3_account_unpublished_fallback_json(h:*mut c_void,out:*mut u8,cap:usize)->isize {
    match as_item(h){Some(Item::Account(a))=>{
        let map:BTreeMap<String,String>=a.fallback_key().into_iter().map(|(k,v)|(k.to_base64(),v.to_base64())).collect();
        match serde_json::to_string(&map){Ok(s)=>text(&s,out,cap),Err(_)=>-1}
    },_=>-1}
}
#[no_mangle] pub unsafe extern "C" fn vdz5_r3_account_mark_published(h:*mut c_void)->i32 {
    match as_item(h){Some(Item::Account(a))=>{a.mark_keys_as_published();0},_=>-1}
}
#[no_mangle] pub unsafe extern "C" fn vdz5_r3_account_sign(h:*mut c_void,data:*const u8,n:usize,out:*mut u8,cap:usize)->isize {
    let m=match in_bytes(data,n){Some(v)=>v,None=>return -1};
    match as_item(h){Some(Item::Account(a))=>text(&a.sign(m).to_base64(),out,cap),_=>-1}
}
#[no_mangle] pub unsafe extern "C" fn vdz5_r3_olm_outbound(account:*mut c_void,identity:*const u8,ilen:usize,otk:*const u8,klen:usize)->*mut c_void {
    let identity=match in_str(identity,ilen).and_then(|s|Curve25519PublicKey::from_base64(s).ok()){Some(v)=>v,None=>return ptr::null_mut()};
    let otk=match in_str(otk,klen).and_then(|s|Curve25519PublicKey::from_base64(s).ok()){Some(v)=>v,None=>return ptr::null_mut()};
    match as_item(account){Some(Item::Account(a))=>match a.create_outbound_session(OC::version_1(),identity,otk){Ok(s)=>boxed(Item::Olm(s)),Err(_)=>ptr::null_mut()},_=>ptr::null_mut()}
}
#[no_mangle] pub unsafe extern "C" fn vdz5_r3_olm_inbound(account:*mut c_void,sender_key:*const u8,klen:usize,prekey:*const u8,mlen:usize,plain:*mut u8,cap:usize)->*mut c_void {
    let sender=match in_str(sender_key,klen).and_then(|s|Curve25519PublicKey::from_base64(s).ok()){Some(v)=>v,None=>return ptr::null_mut()};
    let msg=match in_str(prekey,mlen).and_then(|s|PreKeyMessage::from_base64(s).ok()){Some(v)=>v,None=>return ptr::null_mut()};
    // Prevent consuming a one-time key when the caller's buffer is obviously too small.
    if cap < mlen || plain.is_null() {return ptr::null_mut();}
    match as_item(account){Some(Item::Account(a))=>match a.create_inbound_session(OC::version_1(),sender,&msg){
        Ok(s)=>{if write(&s.plaintext,plain,cap)<0 {ptr::null_mut()} else {boxed(Item::Olm(s.session))}},
        Err(_)=>ptr::null_mut()},_=>ptr::null_mut()}
}
#[no_mangle] pub unsafe extern "C" fn vdz5_r3_olm_encrypt(h:*mut c_void,data:*const u8,n:usize,out:*mut u8,cap:usize)->isize {
    let p=match in_bytes(data,n){Some(v)=>v,None=>return -1};
    // Refuse an undersized output BEFORE advancing the sending ratchet.
    if out.is_null() || cap < n.saturating_mul(2).saturating_add(2048) {return -1;}
    // Senders must persist the updated encrypted pickle BEFORE transmitting output.
    match as_item(h){Some(Item::Olm(s))=>match s.encrypt(p){Ok(m)=>match serde_json::to_vec(&m){Ok(v)=>write(&v,out,cap),Err(_)=>-1},Err(_)=>-1},_=>-1}
}
#[no_mangle] pub unsafe extern "C" fn vdz5_r3_olm_decrypt(h:*mut c_void,message:*const u8,n:usize,out:*mut u8,cap:usize)->isize {
    let m=match in_bytes(message,n).and_then(|b|serde_json::from_slice::<OlmMessage>(b).ok()){Some(m)=>m,None=>return -1};
    if out.is_null() || cap < n {return -1;}
    match as_item(h){Some(Item::Olm(s))=>match s.decrypt(&m){Ok(v)=>write(&v,out,cap),Err(_)=>-1},_=>-1}
}
#[no_mangle] pub extern "C" fn vdz5_r3_megolm_outbound_new()->*mut c_void {boxed(Item::Out(GroupSession::new(MC::version_1())))}
#[no_mangle] pub unsafe extern "C" fn vdz5_r3_megolm_session_key(h:*mut c_void,out:*mut u8,cap:usize)->isize {
    match as_item(h){Some(Item::Out(s))=>text(&s.session_key().to_base64(),out,cap),_=>-1}
}
#[no_mangle] pub unsafe extern "C" fn vdz5_r3_megolm_inbound_new(key:*const u8,n:usize)->*mut c_void {
    match in_str(key,n).and_then(|s|SessionKey::from_base64(s).ok()){
        Some(k)=>boxed(Item::In(InboundGroupSession::new(&k,MC::version_1()))),None=>ptr::null_mut()}
}
#[no_mangle] pub unsafe extern "C" fn vdz5_r3_megolm_encrypt(h:*mut c_void,data:*const u8,n:usize,out:*mut u8,cap:usize)->isize {
    let p=match in_bytes(data,n){Some(p)=>p,None=>return -1};
    if out.is_null() || cap < n.saturating_mul(2).saturating_add(2048) {return -1;}
    match as_item(h){Some(Item::Out(s))=>text(&s.encrypt(p).to_base64(),out,cap),_=>-1}
}
#[no_mangle] pub unsafe extern "C" fn vdz5_r3_megolm_decrypt(h:*mut c_void,message:*const u8,n:usize,out:*mut u8,cap:usize)->isize {
    let msg=match in_str(message,n).and_then(|s|MegolmMessage::from_base64(s).ok()){Some(m)=>m,None=>return -1};
    if out.is_null() || cap < n {return -1;}
    match as_item(h){Some(Item::In(s))=>match s.decrypt(&msg){Ok(v)=>write(&v.plaintext,out,cap),Err(_)=>-1},_=>-1}
}
#[no_mangle] pub unsafe extern "C" fn vdz5_r3_session_id(h:*mut c_void,out:*mut u8,cap:usize)->isize {
    match as_item(h){Some(Item::Olm(s))=>text(&s.session_id(),out,cap),Some(Item::Out(s))=>text(&s.session_id(),out,cap),Some(Item::In(s))=>text(&s.session_id(),out,cap),_=>-1}
}
// Encrypted pickles only. The 32-byte key MUST come from OS CSPRNG and be stored
// by the host app in a protected store, never logged or hardcoded.
#[no_mangle] pub unsafe extern "C" fn vdz5_r3_pickle_encrypted(h:*mut c_void,key:*const u8,klen:usize,out:*mut u8,cap:usize)->isize {
    let k=match key_32(key,klen){Some(k)=>k,None=>return -1};
    let data=match as_item(h){Some(Item::Account(v))=>v.pickle().encrypt(k),Some(Item::Olm(v))=>v.pickle().encrypt(k),Some(Item::Out(v))=>v.pickle().encrypt(k),Some(Item::In(v))=>v.pickle().encrypt(k),None=>return -1};
    text(&data,out,cap)
}
#[no_mangle] pub unsafe extern "C" fn vdz5_r3_unpickle_encrypted(kind:u32,data:*const u8,n:usize,key:*const u8,klen:usize)->*mut c_void {
    let d=match in_str(data,n){Some(s)=>s,None=>return ptr::null_mut()};
    let k=match key_32(key,klen){Some(k)=>k,None=>return ptr::null_mut()};
    match kind {
        ACCOUNT=>match AccountPickle::from_encrypted(d,k){Ok(v)=>boxed(Item::Account(v.into())),Err(_)=>ptr::null_mut()},
        OLM=>match SessionPickle::from_encrypted(d,k){Ok(v)=>boxed(Item::Olm(v.into())),Err(_)=>ptr::null_mut()},
        OUT_GROUP=>match GroupSessionPickle::from_encrypted(d,k){Ok(v)=>boxed(Item::Out(v.into())),Err(_)=>ptr::null_mut()},
        IN_GROUP=>match InboundGroupSessionPickle::from_encrypted(d,k){Ok(v)=>boxed(Item::In(v.into())),Err(_)=>ptr::null_mut()},
        _=>ptr::null_mut(),
    }
}


// Exercise the C ABI itself, not only high-level Rust crypto. All objects are
// temporary; no Matrix account, network calls, files, or durable identities.
struct Guard(*mut c_void);
impl Drop for Guard { fn drop(&mut self){unsafe { vdz5_r3_release(self.0) }} }
fn probe_r3_ffi()->Result<(),()> {
  unsafe {
    let a=Guard(vdz5_r3_account_new());let b=Guard(vdz5_r3_account_new());
    if a.0.is_null() || b.0.is_null(){return Err(());}
    if vdz5_r3_account_generate_otk(b.0,1)!=0 {return Err(());}
    let mut buf=[0u8;8192];
    let n=vdz5_r3_account_unpublished_otk_json(b.0,buf.as_mut_ptr(),buf.len());
    if n<1{return Err(());}
    let keys:BTreeMap<String,String>=serde_json::from_slice(&buf[..n as usize]).map_err(|_|())?;
    let otk=keys.values().next().ok_or(())?.clone();
    if vdz5_r3_account_mark_published(b.0)!=0{return Err(());}
    let n=vdz5_r3_account_identity(b.0,2,buf.as_mut_ptr(),buf.len());
    if n<1{return Err(());}
    let b_curve=buf[..n as usize].to_vec();
    let alice_s=Guard(vdz5_r3_olm_outbound(a.0,b_curve.as_ptr(),b_curve.len(),otk.as_ptr(),otk.len()));
    if alice_s.0.is_null(){return Err(());}
    let hello=b"VDZ R3 FFI OLM";
    let n=vdz5_r3_olm_encrypt(alice_s.0,hello.as_ptr(),hello.len(),buf.as_mut_ptr(),buf.len());
    if n<1{return Err(());}
    let m:OlmMessage=serde_json::from_slice(&buf[..n as usize]).map_err(|_|())?;
    let prekey=match m{OlmMessage::PreKey(v)=>v.to_base64(),_=>return Err(())};
    let n=vdz5_r3_account_identity(a.0,2,buf.as_mut_ptr(),buf.len());
    if n<1{return Err(());}
    let a_curve=buf[..n as usize].to_vec();
    let mut plain=[0u8;8192];
    let bob_s=Guard(vdz5_r3_olm_inbound(b.0,a_curve.as_ptr(),a_curve.len(),prekey.as_ptr(),prekey.len(),plain.as_mut_ptr(),plain.len()));
    if bob_s.0.is_null() || &plain[..hello.len()]!=hello{return Err(());}
    let reply=b"R3 olm response";
    let n=vdz5_r3_olm_encrypt(bob_s.0,reply.as_ptr(),reply.len(),buf.as_mut_ptr(),buf.len());
    if n<1{return Err(());}
    let msg=buf[..n as usize].to_vec();
    let n=vdz5_r3_olm_decrypt(alice_s.0,msg.as_ptr(),msg.len(),plain.as_mut_ptr(),plain.len());
    if n!=reply.len() as isize || &plain[..n as usize]!=reply{return Err(());}
    let pickle_key=[0x93u8;32]; // TEST ONLY: not suitable for real account state.
    let n=vdz5_r3_pickle_encrypted(alice_s.0,pickle_key.as_ptr(),32,buf.as_mut_ptr(),buf.len());
    if n<1 {return Err(());}
    let session_back=Guard(vdz5_r3_unpickle_encrypted(OLM,buf.as_ptr(),n as usize,pickle_key.as_ptr(),32));
    if session_back.0.is_null(){return Err(());}
    let out=Guard(vdz5_r3_megolm_outbound_new());
    if out.0.is_null(){return Err(());}
    let n=vdz5_r3_megolm_session_key(out.0,buf.as_mut_ptr(),buf.len());
    if n<1{return Err(());}
    let key=buf[..n as usize].to_vec();
    let receiver=Guard(vdz5_r3_megolm_inbound_new(key.as_ptr(),key.len()));
    if receiver.0.is_null(){return Err(());}
    let hello=b"VDZ R3 FFI MEGOLM";
    let n=vdz5_r3_megolm_encrypt(out.0,hello.as_ptr(),hello.len(),buf.as_mut_ptr(),buf.len());
    if n<1{return Err(());}
    let cipher=buf[..n as usize].to_vec();
    let n=vdz5_r3_megolm_decrypt(receiver.0,cipher.as_ptr(),cipher.len(),plain.as_mut_ptr(),plain.len());
    if n!=hello.len() as isize || &plain[..n as usize]!=hello{return Err(());}
    let n=vdz5_r3_pickle_encrypted(receiver.0,pickle_key.as_ptr(),32,buf.as_mut_ptr(),buf.len());
    if n<1{return Err(());}
    let imported=Guard(vdz5_r3_unpickle_encrypted(IN_GROUP,buf.as_ptr(),n as usize,pickle_key.as_ptr(),32));
    if imported.0.is_null(){return Err(());}
    Ok(())
  }
}
#[no_mangle] pub extern "C" fn vdz5_r3_ffi_selftest()->u32 {
    if probe_r3_ffi().is_ok(){0}else{4}
}
fn probe_r3_olm()->Result<(),()> {
    let alice=Account::new();let mut bob=Account::new();
    bob.generate_one_time_keys(1);
    let otk=*bob.one_time_keys().values().next().ok_or(())?;
    let mut a=alice.create_outbound_session(OC::version_1(),bob.curve25519_key(),otk).map_err(|_|())?;
    let m=a.encrypt(b"R3 olm roundtrip").map_err(|_|())?;
    let pre=match m {OlmMessage::PreKey(p)=>p,_=>return Err(())};
    let b=bob.create_inbound_session(OC::version_1(),alice.curve25519_key(),&pre).map_err(|_|())?;
    if b.plaintext!=b"R3 olm roundtrip" {return Err(());}
    let mut b=b.session;
    let pickle_key=[0x3Au8;32]; // Test-only; NO production use.
    let saved_a=a.pickle().encrypt(&pickle_key);
    a=SessionPickle::from_encrypted(&saved_a,&pickle_key).map_err(|_|())?.into();
    let reply:OlmMessage=b.encrypt(b"R3 reply").map_err(|_|())?.into();
    if a.decrypt(&reply).map_err(|_|())?!=b"R3 reply" {return Err(());}
    // Check wrong key rejected.
    if SessionPickle::from_encrypted(&saved_a,&[0xFE;32]).is_ok(){return Err(());}
    let saved_account=bob.pickle().encrypt(&pickle_key);
    let recovered:Account=AccountPickle::from_encrypted(&saved_account,&pickle_key).map_err(|_|())?.into();
    if recovered.ed25519_key()!=bob.ed25519_key() || recovered.curve25519_key()!=bob.curve25519_key(){return Err(());}
    Ok(())
}
fn probe_r3_megolm()->Result<(),()> {
    let key=[0x7Au8;32]; // Test-only; NO production use.
    let mut sender=GroupSession::new(MC::version_1());
    let mut receiver=InboundGroupSession::new(&sender.session_key(),MC::version_1());
    let first=sender.encrypt(b"R3 megolm 0");
    if receiver.decrypt(&first).map_err(|_|())?.plaintext!=b"R3 megolm 0"{return Err(());}
    let sender_pickle=sender.pickle().encrypt(&key);
    sender=GroupSessionPickle::from_encrypted(&sender_pickle,&key).map_err(|_|())?.into();
    let receiver_pickle=receiver.pickle().encrypt(&key);
    receiver=InboundGroupSessionPickle::from_encrypted(&receiver_pickle,&key).map_err(|_|())?.into();
    let second=sender.encrypt(b"R3 megolm 1");
    let dec=receiver.decrypt(&second).map_err(|_|())?;
    if dec.plaintext!=b"R3 megolm 1" || dec.message_index!=1 {return Err(());}
    if GroupSessionPickle::from_encrypted(&sender_pickle,&[0xFE;32]).is_ok(){return Err(());}
    Ok(())
}
#[no_mangle] pub extern "C" fn vdz5_r3_bridge_selftest()->u32 {
    (if probe_r3_olm().is_ok(){0}else{1})|(if probe_r3_megolm().is_ok(){0}else{2})
}
#[cfg(test)] mod tests {
  #[test] fn olm_state_roundtrip(){assert!(super::probe_r3_olm().is_ok());}
  #[test] fn megolm_state_roundtrip(){assert!(super::probe_r3_megolm().is_ok());}
  #[test] fn ffi_roundtrip(){assert!(super::probe_r3_ffi().is_ok());}
  #[test] fn ffi_handles(){unsafe{
    let a=super::vdz5_r3_account_new();assert!(!a.is_null());
    let mut buf=[0u8;256];
    assert!(super::vdz5_r3_account_identity(a,2,buf.as_mut_ptr(),buf.len())>0);
    assert!(super::vdz5_r3_account_identity(a,99,buf.as_mut_ptr(),buf.len())<0);
    let key=[0x77u8;32];
    let mut pickle=vec![0u8;8192];
    let n=super::vdz5_r3_pickle_encrypted(a,key.as_ptr(),32,pickle.as_mut_ptr(),pickle.len());
    assert!(n>0);
    let imported=super::vdz5_r3_unpickle_encrypted(1,pickle.as_ptr(),n as usize,key.as_ptr(),32);
    assert!(!imported.is_null());
    let n1=super::vdz5_r3_account_identity(imported,2,buf.as_mut_ptr(),buf.len());
    assert!(n1>0);
    super::vdz5_r3_release(imported);super::vdz5_r3_release(a);
  }}
}

