function setRedirectToHome() {
  // Cancel any previous timer
  clearTimeout(document.timer);

  // Redirect after 3 minutes if @origin is set (Kiosk mode)
  document.timer = setTimeout(function(){
    if (document.origin != '') {
      $('ul.vertical-nav').animate({left: '-200%'}, 500, function() {
        setTimeout(function(){
          window.location = "/";
        }, 500);
      })
    }
  }, 180000); // 3 minutes
}

$(function() {
  // Call redirect timer function
  setRedirectToHome();

  //resizeIcons();

  $('a.btn-home').click(function(e) {
    e.preventDefault();
    var anchor = $(this), h;
    h = anchor.attr('href');
    $('ul.vertical-nav').animate({left: '-200%'}, 500, function() {
      window.location = h;
    })
  });
});
