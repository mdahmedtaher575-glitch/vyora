/* VYORA live features: Supabase video publishing, feed, community polls and premiere schedule. */
(() => {
  const client = window.supabaseClient;
  if (!client) return;
  const $ = (id) => document.getElementById(id);
  const message = (text) => {
    let el = $('vyoraLiveMessage');
    if (!el) {
      el = document.createElement('div');
      el.id = 'vyoraLiveMessage';
      el.style.cssText = 'position:fixed;bottom:18px;left:50%;transform:translateX(-50%);z-index:100;background:#24202f;color:white;border:1px solid #66528e;padding:12px 18px;border-radius:12px;max-width:90vw';
      document.body.appendChild(el);
    }
    el.textContent = text;
    clearTimeout(el._timer);
    el._timer = setTimeout(() => el.remove(), 5000);
  };
  const escapeText = (s) => String(s || '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  async function currentUser() {
    const { data, error } = await client.auth.getUser();
    if (error) throw error;
    if (!data.user) throw new Error('আগে VYORA-তে Sign in করো।');
    return data.user;
  }
  async function loadFeed() {
    const grid = $('grid');
    if (!grid) return;
    const { data, error } = await client.from('videos')
      .select('id,title,description,video_url,thumbnail_url,category,created_at,channels(name,handle)')
      .eq('visibility','public').eq('processing_status','ready')
      .order('created_at',{ascending:false}).limit(40);
    if (error) { console.warn('VYORA feed:', error.message); return; }
    grid.querySelectorAll('[data-vyora-live="1"]').forEach(n => n.remove());
    (data || []).forEach(v => {
      if (!v.video_url) return;
      const card = document.createElement('article');
      card.className = 'video';
      card.dataset.vyoraLive = '1';
      card.dataset.category = String(v.category || 'entertainment').toLowerCase();
      card.dataset.title = String(v.title || '').toLowerCase();
      const thumb = document.createElement('div');
      thumb.className = 'thumb';
      if (v.thumbnail_url) {
        const img = document.createElement('img'); img.src = v.thumbnail_url; img.alt = v.title || 'Video thumbnail'; thumb.appendChild(img);
      } else {
        thumb.style.cssText = 'display:grid;place-items:center;background:#211a35;color:white;font-size:48px';
        thumb.textContent = '▶';
      }
      const info = document.createElement('div'); info.className = 'vinfo';
      const avatar = document.createElement('div'); avatar.className = 'channel-avatar';
      avatar.textContent = (v.channels?.name || 'V').slice(0,1).toUpperCase();
      const details = document.createElement('div');
      const title = document.createElement('h3'); title.textContent = v.title || 'Untitled video';
      const channel = document.createElement('p'); channel.textContent = v.channels?.name || 'VYORA Creator';
      const date = document.createElement('p'); date.textContent = new Date(v.created_at).toLocaleDateString();
      details.append(title,channel,date); info.append(avatar,details); card.append(thumb,info);
      thumb.addEventListener('click', () => {
        if (typeof window.openPlayer === 'function') window.openPlayer(v.video_url,v.title || 'VYORA video');
        else window.open(v.video_url,'_blank','noopener');
      });
      grid.prepend(card);
    });
    if (typeof window.filterVideos === 'function') window.filterVideos();
  }
  async function publishVideo(event) {
    const file = event?.target?.files?.[0];
    if (!file) return;
    event.target.value = '';
    try {
      const user = await currentUser();
      if (!file.type.startsWith('video/')) throw new Error('একটি ভিডিও ফাইল বেছে নাও।');
      if (file.size > 200 * 1024 * 1024) throw new Error('ভিডিও সর্বোচ্চ ২০০ MB হতে পারবে।');
      const title = window.prompt('ভিডিওর শিরোনাম লিখো:',file.name.replace(/\\.[^.]+$/,''));
      if (!title || !title.trim()) return;
      const { data: channel, error: channelError } = await client.from('channels').select('id').eq('owner_id',user.id).single();
      if (channelError || !channel) throw new Error('তোমার চ্যানেল পাওয়া যায়নি। আবার Sign in করো।');
      const path = user.id + '/' + crypto.randomUUID() + '-' + file.name.replace(/[^a-zA-Z0-9._-]/g,'_');
      const { error: storageError } = await client.storage.from('videos').upload(path,file,{contentType:file.type,upsert:false});
      if (storageError) throw storageError;
      const { data: urlData } = client.storage.from('videos').getPublicUrl(path);
      const { error: rowError } = await client.from('videos').insert({
        channel_id:channel.id,title:title.trim(),video_url:urlData.publicUrl,
        category:'Entertainment',visibility:'public',processing_status:'ready'
      });
      if (rowError) {
        await client.storage.from('videos').remove([path]);
        throw rowError;
      }
      message('ভিডিও VYORA-তে প্রকাশিত হয়েছে।');
      await loadFeed();
    } catch (err) { message('আপলোড হয়নি: ' + (err.message || 'অজানা সমস্যা')); }
  }
  window.uploadVideo = publishVideo;

  function addCommunityTools() {
    const section = $('community');
    if (!section || $('vyoraPollComposer')) return;
    const panel = document.createElement('div');
    panel.className = 'panel'; panel.id = 'vyoraPollComposer'; panel.style.marginTop = '14px';
    panel.innerHTML = '<h2>Community poll</h2><input class="field" id="vyoraPollQuestion" maxlength="500" placeholder="Poll question"><input class="field" id="vyoraPollA" maxlength="200" placeholder="Option 1"><input class="field" id="vyoraPollB" maxlength="200" placeholder="Option 2"><button class="btn primary" id="vyoraPublishPoll">Publish poll</button><div id="vyoraPollFeed" class="list" style="margin-top:14px"></div>';
    section.appendChild(panel);
    $('vyoraPublishPoll').addEventListener('click', async () => {
      try {
        const user = await currentUser();
        const question = $('vyoraPollQuestion').value.trim();
        const options = [$('vyoraPollA').value.trim(),$('vyoraPollB').value.trim()].filter(Boolean);
        if (!question || options.length < 2) throw new Error('প্রশ্ন ও অন্তত দুটি অপশন দাও।');
        const { data: channel, error: ce } = await client.from('channels').select('id').eq('owner_id',user.id).single();
        if (ce || !channel) throw ce || new Error('চ্যানেল পাওয়া যায়নি।');
        const { data: post, error: pe } = await client.from('community_posts').insert({channel_id:channel.id,body:question,post_type:'poll'}).select('id').single();
        if (pe) throw pe;
        const { error: oe } = await client.from('poll_options').insert(options.map((option_text,position)=>({post_id:post.id,option_text,position})));
        if (oe) throw oe;
        $('vyoraPollQuestion').value = $('vyoraPollA').value = $('vyoraPollB').value = '';
        message('কমিউনিটি পোল প্রকাশিত হয়েছে।');
        await loadPolls();
      } catch (err) { message('পোল প্রকাশ হয়নি: ' + (err.message || 'সমস্যা হয়েছে')); }
    });
  }
  async function loadPolls() {
    const host = $('vyoraPollFeed'); if (!host) return;
    const { data: posts, error } = await client.from('community_posts').select('id,body,created_at,channels(name)').eq('post_type','poll').order('created_at',{ascending:false}).limit(20);
    if (error) { console.warn('Poll feed:',error.message); return; }
    host.replaceChildren();
    for (const post of posts || []) {
      const { data: options } = await client.from('poll_options').select('id,option_text').eq('post_id',post.id).order('position');
      const box = document.createElement('div'); box.className = 'item'; box.style.display = 'block';
      const heading = document.createElement('strong'); heading.textContent = post.body; box.appendChild(heading);
      for (const option of options || []) {
        const b = document.createElement('button'); b.className = 'chip'; b.style.margin = '8px 6px 0 0'; b.textContent = option.option_text;
        b.addEventListener('click',async()=>{
          try { const user = await currentUser(); const { error } = await client.from('poll_votes').insert({option_id:option.id,user_id:user.id}); if(error) throw error; message('তোমার ভোট জমা হয়েছে।'); b.disabled=true; }
          catch(err){message('ভোট দেওয়া যায়নি: '+(err.message||'সমস্যা হয়েছে'));}
        });
        box.appendChild(b);
      }
      host.appendChild(box);
    }
  }
  function addPremiereCountdown() {
    const live = $('live'); if (!live || $('vyoraPremiere')) return;
    const box = document.createElement('div'); box.className='panel'; box.id='vyoraPremiere'; box.style.marginTop='14px';
    box.innerHTML='<h2>Premiere countdown</h2><p class="muted">Set a countdown for your upcoming premiere.</p><input class="field" id="vyoraPremiereTime" type="datetime-local"><button class="btn primary" id="vyoraPremiereStart">Start countdown</button><h2 id="vyoraPremiereClock" aria-live="polite">Not scheduled</h2>';
    live.appendChild(box);
    let timer;
    $('vyoraPremiereStart').addEventListener('click',()=>{
      const target=new Date($('vyoraPremiereTime').value).getTime();
      if(!Number.isFinite(target)||target<=Date.now()){message('ভবিষ্যতের তারিখ ও সময় বেছে নাও।');return;}
      clearInterval(timer);
      const tick=()=>{const left=target-Date.now();if(left<=0){$('vyoraPremiereClock').textContent='Premiere time!';clearInterval(timer);return;}
        const d=Math.floor(left/86400000),h=Math.floor(left%86400000/3600000),m=Math.floor(left%3600000/60000),s=Math.floor(left%60000/1000);
        $('vyoraPremiereClock').textContent=d+'d '+h+'h '+m+'m '+s+'s';};
      tick();timer=setInterval(tick,1000);
    });
  }
  addCommunityTools();
  addPremiereCountdown();
  loadFeed();
  loadPolls();
  client.auth.onAuthStateChange(()=>{setTimeout(()=>{loadFeed();loadPolls();},0);});
  document.addEventListener('visibilitychange',()=>{if(!document.hidden)loadFeed();});
})();