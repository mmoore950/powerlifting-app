// Shared by the browser derivative and Node adapter; JSON.parse alone loses duplicate keys.
export function parseStrictJSON(text) {
  const value=JSON.parse(text);let i=0;
  const require=(ok,message)=>{if(!ok)throw Error(message);};
  const space=()=>{while(/\s/.test(text[i]??'')&&i<text.length)i++;};
  const string=()=>{const start=i++;while(i<text.length){if(text[i]==='\\'){i+=2;continue;}if(text[i++]==='"')break;}return JSON.parse(text.slice(start,i));};
  const walk=(depth=0)=>{
    require(depth<=32,'JSON exceeds nesting limit');space();
    if(text[i]==='{') {i++;space();const seen=new Set();if(text[i]==='}'){i++;return;}
      while(true){space();const key=string();require(!seen.has(key),'Duplicate JSON key: '+key);seen.add(key);space();i++;walk(depth+1);space();if(text[i++]==='}')break;}
    } else if(text[i]==='[') {i++;space();if(text[i]===']'){i++;return;}while(true){walk(depth+1);space();if(text[i++]===']')break;}}
    else if(text[i]==='"')string();else {while(i<text.length&&!/[\s,}\]]/.test(text[i]))i++;}
  };walk();return value;
}
