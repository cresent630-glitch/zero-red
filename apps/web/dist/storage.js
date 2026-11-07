(function(root){
  function createStorage(factory){let pending=null;
    function open(){if(!pending)pending=new Promise((resolve,reject)=>{const request=factory.open('zero-red-videos',3);request.onupgradeneeded=()=>{for(const name of ['videos','documents','downloads'])if(!request.result.objectStoreNames.contains(name))request.result.createObjectStore(name,{keyPath:'id'})};request.onblocked=()=>{pending=null;reject(Error('Close other preview tabs, then try again.'))};request.onsuccess=()=>{request.result.onversionchange=()=>{request.result.close();pending=null};resolve(request.result)};request.onerror=()=>{pending=null;reject(request.error)}});return pending}
    async function operation(mode,action,storeName='videos'){const db=await open();return new Promise((resolve,reject)=>{const transaction=db.transaction(storeName,mode);let value;const request=action(transaction.objectStore(storeName));request.onsuccess=()=>value=request.result;transaction.oncomplete=()=>resolve(value);transaction.onerror=()=>reject(transaction.error);transaction.onabort=()=>reject(transaction.error||Error('Storage transaction aborted'))})}
    return {open,operation};
  }
  const api={createStorage};root.ZeroStorage=api;if(typeof module!=='undefined')module.exports=api;
})(globalThis);
