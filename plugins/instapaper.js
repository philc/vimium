// got it from http://github.com/llimllib/vimium (but change to your instapaper bookmarlet)
function runInstapaper() {
    window.location = "javascript:function iprl5(){var d=document,z=d.createElement('scr'+'ipt'),b=d.body,l=d.location;try{if(!b)throw(0);d.title='(Saving...) '+d.title;z.setAttribute('src',l.protocol+'//www.instapaper.com/j/hI1McPuK4awE?u='+encodeURIComponent(l.href)+'&t='+(new Date().getTime()));b.appendChild(z);}catch(e){alert('Please wait until the page has loaded.');}}iprl5();void(0)";
}
