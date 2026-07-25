let currentURL="";



// ambil video aktif

async function loadVideo(){


let tabs =
await browser.tabs.query({

active:true,

currentWindow:true

});


let tab=tabs[0];


if(!tab.url){

return;

}



try{


let url =
new URL(tab.url);



let id =
url.searchParams.get("v");



if(id){


currentURL =
"https://www.youtube.com/watch?v="+id;



document.getElementById("url")
.innerText=currentURL;



}

else{


document.getElementById("url")
.innerText=
"Tidak ada video";


}


}
catch(e){

document.getElementById("url")
.innerText=
"URL error";

}



}




async function updateCount(){


let data =
await browser.storage.local.get("videos");


let videos =
data.videos || [];



document.getElementById("count")
.innerText =
"Total: "+videos.length;


}



loadVideo();

updateCount();





// SAVE

document.getElementById("save")
.onclick=async()=>{


if(!currentURL){

alert("Video tidak ditemukan");

return;

}



let data =
await browser.storage.local.get("videos");


let videos =
data.videos || [];



let sub =
document.getElementById("sub").value;


let resolution =
document.getElementById("resolution").value;



let index =
videos.findIndex(
    item => item.url === currentURL
);



let item = {

    url: currentURL,

    sub: sub,

    resolution: resolution,

    saved: new Date().toISOString()

};



if(index !== -1){

    // update data lama

    videos[index] = item;


}
else{

    // tambah baru

    videos.push(item);

}



await browser.storage.local.set({

videos:videos

});



updateCount();


alert("Saved");



};






// OPEN FULL PAGE

document.getElementById("open")
.onclick=()=>{


browser.tabs.create({

url:
browser.runtime.getURL(
"manager.html"
)

});


};