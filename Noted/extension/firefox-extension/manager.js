async function loadJSON(){


    let data =
    await browser.storage.local.get("videos");


    let videos =
    data.videos || [];



    document.getElementById("count")
    .innerText =
    "Total data: " + videos.length;



    document.getElementById("json")
    .value =
    JSON.stringify(
        videos,
        null,
        4
    );


}



loadJSON();




// DOWNLOAD JSON

document.getElementById("download")
.onclick = async()=>{


    let data =
    await browser.storage.local.get("videos");


    let json =
    JSON.stringify(
        data.videos || [],
        null,
        4
    );



    let blob =
    new Blob(
        [json],
        {
            type:"application/json"
        }
    );



    let url =
    URL.createObjectURL(blob);



    let a =
    document.createElement("a");


    a.href=url;

    a.download=
    "youtube-saved.json";


    a.click();



    setTimeout(()=>{

        URL.revokeObjectURL(url);

    },1000);



};





// CLEAR

document.getElementById("clear")
.onclick = async()=>{


    let ok =
    confirm(
        "Hapus semua data?"
    );



    if(ok){


        await browser.storage.local.remove(
            "videos"
        );


        loadJSON();


    }


};