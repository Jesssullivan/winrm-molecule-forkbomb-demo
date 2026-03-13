// WinRM Forkbomb Demo - GitHub repo browser SPA

(function () {
  'use strict';

  var owner = document.querySelector('meta[name="github-owner"]').content;
  var repo = document.querySelector('meta[name="github-repo"]').content;
  var apiBase = 'https://api.github.com/repos/' + owner + '/' + repo;

  var repoInfoEl = document.getElementById('repo-info');
  var fileTreeEl = document.getElementById('file-tree');
  var fileContentEl = document.getElementById('file-content');
  var repoLinkEl = document.getElementById('repo-link');

  repoLinkEl.href = 'https://github.com/' + owner + '/' + repo;
  repoLinkEl.textContent = owner + '/' + repo;

  function handleRateLimit(response) {
    if (response.status === 403 || response.status === 429) {
      var resetHeader = response.headers.get('X-RateLimit-Reset');
      var resetTime = resetHeader
        ? new Date(parseInt(resetHeader, 10) * 1000).toLocaleTimeString()
        : 'soon';
      var el = document.createElement('div');
      el.className = 'rate-limit';
      el.textContent = 'GitHub API rate limit reached. Resets at ' + resetTime +
        '. Try again later or authenticate.';
      repoInfoEl.parentNode.insertBefore(el, repoInfoEl);
      return true;
    }
    return false;
  }

  function fetchJSON(url) {
    return fetch(url).then(function (response) {
      if (handleRateLimit(response)) {
        return Promise.reject(new Error('Rate limited'));
      }
      if (!response.ok) {
        return Promise.reject(new Error('HTTP ' + response.status));
      }
      return response.json();
    });
  }

  // Fetch and display repo metadata
  function loadRepoInfo() {
    repoInfoEl.innerHTML = '<div class="loading">Loading repository info...</div>';
    fetchJSON(apiBase).then(function (data) {
      var html = '';
      if (data.description) {
        html += '<div class="description">' + escapeHtml(data.description) + '</div>';
      }
      html += '<div class="stats">';
      html += '<span>Stars: ' + (data.stargazers_count || 0) + '</span>';
      html += '<span>Forks: ' + (data.forks_count || 0) + '</span>';
      html += '<span>Language: ' + escapeHtml(data.language || 'N/A') + '</span>';
      html += '</div>';
      repoInfoEl.innerHTML = html;
    }).catch(function (err) {
      repoInfoEl.innerHTML = '<div class="error">Failed to load repo info: ' +
        escapeHtml(err.message) + '</div>';
    });
  }

  // Fetch directory contents recursively and build a tree
  function loadTree(path) {
    var url = apiBase + '/contents' + (path ? '/' + path : '');
    return fetchJSON(url).then(function (items) {
      items.sort(function (a, b) {
        // Directories first, then alphabetical
        if (a.type === 'dir' && b.type !== 'dir') return -1;
        if (a.type !== 'dir' && b.type === 'dir') return 1;
        return a.name.localeCompare(b.name);
      });
      return items;
    });
  }

  function renderTree(items, container, depth) {
    items.forEach(function (item) {
      var el = document.createElement('div');
      el.className = 'tree-item ' + (item.type === 'dir' ? 'directory' : 'file');

      var indent = '';
      for (var i = 0; i < depth; i++) {
        indent += '<span class="tree-indent"></span>';
      }

      var icon = item.type === 'dir' ? '+ ' : '  ';
      el.innerHTML = indent + icon + escapeHtml(item.name);
      el.dataset.path = item.path;
      el.dataset.type = item.type;

      if (item.type === 'dir') {
        var childContainer = document.createElement('div');
        childContainer.style.display = 'none';
        childContainer.dataset.loaded = 'false';

        el.addEventListener('click', function (e) {
          e.stopPropagation();
          if (childContainer.dataset.loaded === 'false') {
            childContainer.dataset.loaded = 'true';
            loadTree(item.path).then(function (children) {
              renderTree(children, childContainer, depth + 1);
              childContainer.style.display = 'block';
              el.innerHTML = indent + '- ' + escapeHtml(item.name);
            }).catch(function () {
              childContainer.innerHTML = '<div class="error" style="padding-left:' +
                ((depth + 1) * 1.25) + 'rem">Failed to load</div>';
              childContainer.style.display = 'block';
            });
          } else if (childContainer.style.display === 'none') {
            childContainer.style.display = 'block';
            el.innerHTML = indent + '- ' + escapeHtml(item.name);
          } else {
            childContainer.style.display = 'none';
            el.innerHTML = indent + '+ ' + escapeHtml(item.name);
          }
        });

        container.appendChild(el);
        container.appendChild(childContainer);
      } else {
        el.addEventListener('click', function () {
          loadFileContent(item.path);
          // Mark active
          var prev = document.querySelector('.tree-item.active');
          if (prev) prev.classList.remove('active');
          el.classList.add('active');
        });
        container.appendChild(el);
      }
    });
  }

  // Fetch and display file content
  function loadFileContent(path) {
    fileContentEl.style.display = 'block';
    fileContentEl.innerHTML = '<h3>' + escapeHtml(path) + '</h3>' +
      '<div class="loading">Loading file...</div>';

    var url = apiBase + '/contents/' + path;
    fetchJSON(url).then(function (data) {
      var content;
      if (data.encoding === 'base64' && data.content) {
        try {
          content = atob(data.content.replace(/\n/g, ''));
        } catch (e) {
          content = '[Binary file - cannot display]';
        }
      } else {
        content = data.content || '[Empty file]';
      }

      // Check if file is likely binary
      if (data.size > 500000) {
        content = '[File too large to display (' + Math.round(data.size / 1024) + ' KB)]';
      }

      fileContentEl.innerHTML = '<h3>' + escapeHtml(path) +
        ' <span style="color:#7a7a8a;font-weight:normal">(' +
        formatSize(data.size) + ')</span></h3>' +
        '<pre><code>' + escapeHtml(content) + '</code></pre>';
    }).catch(function (err) {
      fileContentEl.innerHTML = '<h3>' + escapeHtml(path) + '</h3>' +
        '<div class="error">Failed to load: ' + escapeHtml(err.message) + '</div>';
    });
  }

  function formatSize(bytes) {
    if (bytes < 1024) return bytes + ' B';
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
  }

  function escapeHtml(str) {
    var div = document.createElement('div');
    div.appendChild(document.createTextNode(str));
    return div.innerHTML;
  }

  // Initialize
  loadRepoInfo();

  fileTreeEl.innerHTML = '<h2>Repository Files</h2><div class="loading">Loading file tree...</div>';
  loadTree('').then(function (items) {
    fileTreeEl.innerHTML = '<h2>Repository Files</h2>';
    renderTree(items, fileTreeEl, 0);
  }).catch(function (err) {
    fileTreeEl.innerHTML = '<h2>Repository Files</h2>' +
      '<div class="error">Failed to load file tree: ' + escapeHtml(err.message) + '</div>';
  });
})();
