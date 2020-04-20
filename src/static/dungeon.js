window.hero = {tile: null, x: 0, y: 0, dir: 0, dy: -14, phase: 0};
window.dungeon_width = 100;
window.dungeon_height = 100;
window.dungeon_scale = 2;
window.coin_phase = 0;
window.fountain_phase = 0;
window.dungeon_queue = [];
window.dirs = ['right', 'front', 'left', 'back'];
window.coin_sprites = {};
window.fountain_top_sprites = [];
window.fountain_bottom_sprites = [];
window.animation_timeout_handle = null;
window.demon_tile = null;
window.dialog_timeout = null;
window.dungeon_queue_timeout = null;

function resize_dungeon() {
    let width = $('#screen').width();
    let height = $('#screen').height();
    // determine dungeon_scale
    dungeon_scale = 1;
    for (i = 2; i <= 3; i += 1)
        if (dungeon_width * 16 * i < width && dungeon_height * 16 * i < height)
            dungeon_scale = i;
    // shift sprite_container
    let shift_x = (width / 2 - 16 * dungeon_scale * dungeon_width / 2);
    let shift_y = (height / 2 - 16 * dungeon_scale * dungeon_height / 2);
    $('#sprite_container').css({
        left: '' + shift_x + 'px',
        top: '' + shift_y + 'px'});
        
    $('.sprite').each(function(i, sprite) {
        sprite = $(sprite);
        sprite.css({
            width: '' + (16 * dungeon_scale * sprite.data('scale')) + 'px',
            left: (sprite.data('x') * 16 + sprite.data('dx')) * dungeon_scale,
            top: (sprite.data('y') * 16 + sprite.data('dy')) * dungeon_scale,
            'z-index': sprite.data('bg') ? 0 : (sprite.data('y') * 16) * dungeon_scale + sprite.data('z')
        });
    });
    update_hero_sprite();
    let dialog_y = shift_y / 2;
    if (dialog_y < 0)
        dialog_y = 0;
    $('#screen .dialog').css({'font-size': '' + dungeon_scale * 100 + '%',
        'top': '' + dialog_y + 'px'});
}

function animate() {
    hero.phase = (hero.phase + 1) % 4;
    hero.tile.attr('src', '/sprites/0x72/wiz_' +dirs[hero.dir] + hero.phase + '.png');
    if (demon_tile !== null)
        demon_tile.attr('src', '/sprites/0x72/big_demon_idle_anim_f' + hero.phase + '.png');
    coin_phase = (coin_phase + 1) % 4;
    $('.sprite-coin').each(function(i, coin) {
        coin = $(coin);
        let phase = (coin_phase + (coin.data('x') + coin.data('y'))) % 4;
        coin.attr('src', '/sprites/0x72/coin_anim_f' + phase + '.png');
    });
    fountain_phase = (fountain_phase + 1) % 3;
    fountain_top_sprites.forEach(function(sprite, i) {
        sprite.attr('src', '/sprites/0x72/wall_fountain_mid_blue_anim_f' + fountain_phase + '.png');
    });
    fountain_bottom_sprites.forEach(function(sprite, i) {
        sprite.attr('src', '/sprites/0x72/wall_fountain_basin_blue_anim_f' + fountain_phase + '.png');
    });
//     // darken
//     $('.sprite').each(function(i, sprite) {
//         sprite = $(sprite);
//         if (!sprite.hasClass('hero')) 
//         {
//             let x = sprite.data('x');
//             let y = sprite.data('y');
//             let dist = (hero.x - x) * (hero.x - x) + (hero.y - y) * (hero.y - y);
//             let opacity = 1.0 - dist * 0.05;
//             if (opacity < 0.1)
//                 opacity = 0.1;
//             sprite.css({
//                 opacity: opacity
//             });
//         }
//     });
}

function load_dungeon(task_slug) {
    api_call('/api/load_dungeon', {slug: task_slug}, function(data) {
        let container = $('#sprite_container');
        container.empty();
        dungeon_width = data.width;
        dungeon_height = data.height;
        resize_dungeon();
        data.tiles.forEach(function(info, i) {
            let tile = $('<img>').addClass('sprite').attr('src', '/sprites/0x72/' + info.sprite + '.png').data({x: info.x, y: info.y, dx: info.dx || 0, dy: info.dy || 0, z: info.z || 0, scale: info.scale || 1, bg: info.bg || false}).appendTo(container);
            if (info.flip_x)
                tile.addClass('flip-x');
            if (info.flip_y)
                tile.addClass('flip-y');
            if (info.hero)
            {
                hero.tile = tile;
                hero.x = info.x;
                hero.y = info.y;
                hero.dir = info.dir;
                tile.addClass('hero');
            }
            if (info.coin) 
            {
                tile.addClass('sprite-coin');
                coin_sprites['' + info.x + '/' + (info.y - 1)] = tile;
            }
            if (info.fountain_top) 
                fountain_top_sprites.push(tile);
            if (info.fountain_bottom) 
                fountain_bottom_sprites.push(tile);
            if (info.demon) 
                demon_tile = tile;
        });
        resize_dungeon();
        if (animation_timeout_handle !== null)
            clearInterval(animation_timeout_handle);
        animation_timeout_handle = setInterval(animate, 250);
    });
}

function enqueue_dungeon_command(data) {
    if (data.command === 'say')
    {
        for (let i = 1; i <= data.message.length; i++)
        {
            let hidden = data.message.substr(i, data.message.length);
            dungeon_queue.push({command: 'say', message: data.message.substr(0, i) + "<span class='invisible'>" + hidden + "</span>", sleep: 0.1});
        }
    }
    else if (data.command === 'forward')
    {
        data.command = 'forward_4';
        data.sleep /= 4;
        for (let i = 0; i < 4; i++)
            dungeon_queue.push(data);
    }
    else
        dungeon_queue.push(data);
    if (dungeon_queue_timeout === null)
        dungeon_queue_timeout = setTimeout(handle_next_dungeon_command, 0);
}

function handle_next_dungeon_command() {
    dungeon_queue_timeout = null;
    let item = dungeon_queue.shift();
    if (typeof(item) !== 'undefined')
    {
        handle_dungeon_command(item);
        if (dungeon_queue.length > 0)
            dungeon_queue_timeout = setTimeout(handle_next_dungeon_command, (item.sleep * 1000) || 0);
    }
}

function update_hero_sprite() {
    if (hero.tile !== null)
    {
        hero.tile.css('left', (hero.x * 16 + hero.tile.data('dx'))  * dungeon_scale);
        hero.tile.css('top', (hero.y * 16 + hero.tile.data('dy')) * dungeon_scale);
        hero.tile.css('z-index', ((hero.y * 16 + hero.tile.data('dy')) + 16) * dungeon_scale);
        hero.tile.attr('src', '/sprites/0x72/wiz_' +dirs[hero.dir] + hero.phase + '.png');
    }
}

function handle_dungeon_command(data) {
    if (data.command === 'forward')
    {
        if (hero.dir === 0)
            hero.x += 1;
        else if (hero.dir === 1)
            hero.y += 1;
        else if (hero.dir === 2)
            hero.x -= 1;
        else if (hero.dir === 3)
            hero.y -= 1;
        update_hero_sprite();
    }
    else if (data.command === 'forward_4')
    {
        if (hero.dir === 0)
            hero.x += 1.0 / 4;
        else if (hero.dir === 1)
            hero.y += 1.0 / 4;
        else if (hero.dir === 2)
            hero.x -= 1.0 / 4;
        else if (hero.dir === 3)
            hero.y -= 1.0 / 4;
        update_hero_sprite();
    }
    else if (data.command === 'turn_left')
    {
        hero.dir = (hero.dir + 3) % 4;
        update_hero_sprite();
    }
    else if (data.command === 'turn_right')
    {
        hero.dir = (hero.dir + 1) % 4;
        update_hero_sprite();
    }
    else if (data.command === 'take_coin')
    {
        // remove coin sprite
        coin_sprites['' + data.x + '/' + data.y].hide();
    }
    else if (data.command === 'say')
    {
        $('#screen .dialog').html(data.message).show();
        (function() {
            if (dialog_timeout != null)
            {
                clearTimeout(dialog_timeout);
                dialog_timeout = null;
            }
            dialog_timeout = setTimeout(function() {
                $('#screen .dialog').fadeOut();
            }, 4000);
        })();
    }
}
