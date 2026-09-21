// Keep long navigation out of the way on small screens.
// With JavaScript disabled, the menu remains open and all links are available.
(() => {
  const navigation = document.querySelector('.docs-navigation');
  if (!navigation) return;

  const mobile = window.matchMedia('(max-width: 760px)');
  const updateNavigation = () => { navigation.open = !mobile.matches; };
  mobile.addEventListener('change', updateNavigation);
  updateNavigation();
})();
