window.canvas_width = 128;
window.canvas_height = 128;
window.canvas_scale = 2;
window.canvas_image = null;

function resize_canvas() {
    let width = $('#screen').width();
    let height = $('#screen').height();
    // determine dungeon_scale
    canvas_scale = 1;
    for (i = 2; i <= 4; i += 1)
        if (canvas_width * i < width && canvas_height * i < height)
            canvas_scale = i;
    $('#sprite_container img').css('width', '' + canvas_width * canvas_scale + 'px');
    $('#sprite_container img').css('height', '' + canvas_height * canvas_scale + 'px');
    // shift sprite_container
    let shift_x = (width / 2 - canvas_scale * canvas_width / 2);
    let shift_y = (height / 2 - canvas_scale * canvas_height / 2);
    $('#sprite_container img').css('left', '' + shift_x + 'px');
    $('#sprite_container img').css('top', '' + shift_y + 'px');
}

function load_canvas() {
    jQuery.get(`/canvas/${session_user_email}/_reset_canvas`, {}, function() {
        canvas_image = $('<img>').attr('src', '/canvas/' + session_user_email + '/?' + + Date.now()).addClass('canvas');
        $('#sprite_container').empty().append(canvas_image);
        resize_canvas();
    });
}
