// Keep the command selectable when JavaScript or clipboard access is unavailable.
(() => {
  const container = document.querySelector('.home-install-command');
  if (!container) return;

  const button = container.querySelector('.copy-command');
  const code = container.querySelector('pre code');
  const feedback = container.querySelector('.copy-feedback');
  if (!button || !code || !feedback) return;

  let resetFeedback;
  button.hidden = false;
  button.addEventListener('click', async () => {
    clearTimeout(resetFeedback);
    feedback.textContent = '';
    button.disabled = true;

    try {
      await navigator.clipboard.writeText(code.textContent.trim());
      feedback.textContent = 'Copied!';
      resetFeedback = setTimeout(() => { feedback.textContent = ''; }, 2000);
    } catch {
      feedback.textContent = 'Could not copy. Select the command and copy it manually.';
    } finally {
      button.disabled = false;
    }
  });
})();
