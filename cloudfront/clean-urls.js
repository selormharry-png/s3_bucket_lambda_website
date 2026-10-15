// CloudFront Function (viewer request): clean URLs for the static site.
//   /          -> /index.html
//   /about     -> /about.html
//   /about/    -> /about/index.html
// Anything with a file extension (/style.css, /images/hero.jpg) is untouched.
function handler(event) {
  var request = event.request;
  var uri = request.uri;

  if (uri.endsWith('/')) {
    request.uri += 'index.html';
  } else if (!uri.includes('.')) {
    request.uri += '.html';
  }
  return request;
}
