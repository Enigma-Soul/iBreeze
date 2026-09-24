// iBreeze 插件运行时 · BreezeHtml
//
// Breeze 在 Rust 侧提供了一套 cheerio 常用子集的 HTML 解析 API，插件普遍依赖它
// 抓取网页。这里用纯 JS 实现同一套接口：`BreezeHtml.load(html)` 返回 `$`，
// 支持文档里列出的选择器、遍历与读取方法。
(function () {
  "use strict";

  var VOID_TAGS = {
    area: 1, base: 1, br: 1, col: 1, embed: 1, hr: 1, img: 1, input: 1,
    link: 1, meta: 1, param: 1, source: 1, track: 1, wbr: 1
  };
  var RAW_TEXT_TAGS = { script: 1, style: 1 };

  // ---------- 解析 ----------

  function createNode(type, name) {
    return { type: type, name: name || "", attribs: {}, children: [], parent: null, value: "" };
  }

  function parseAttributes(text) {
    var attribs = {};
    var pattern = /([^\s"'/=>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;
    var match;
    while ((match = pattern.exec(text)) !== null) {
      var name = match[1].toLowerCase();
      var value = match[2] !== undefined ? match[2]
        : match[3] !== undefined ? match[3]
          : match[4] !== undefined ? match[4] : "";
      attribs[name] = decodeEntities(value);
    }
    return attribs;
  }

  function decodeEntities(text) {
    return String(text).replace(/&(#x?[0-9a-fA-F]+|[a-zA-Z]+);/g, function (raw, entity) {
      if (entity.charAt(0) === "#") {
        var code = entity.charAt(1).toLowerCase() === "x"
          ? parseInt(entity.slice(2), 16)
          : parseInt(entity.slice(1), 10);
        return Number.isFinite(code) ? String.fromCodePoint(code) : raw;
      }
      var named = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " " };
      return named[entity.toLowerCase()] !== undefined ? named[entity.toLowerCase()] : raw;
    });
  }

  function parseHTML(html) {
    var root = createNode("root");
    var stack = [root];
    var index = 0;
    var text = String(html);

    function current() { return stack[stack.length - 1]; }

    function pushText(value) {
      if (!value) return;
      var node = createNode("text");
      node.value = decodeEntities(value);
      node.parent = current();
      current().children.push(node);
    }

    while (index < text.length) {
      var open = text.indexOf("<", index);
      if (open === -1) {
        pushText(text.slice(index));
        break;
      }
      pushText(text.slice(index, open));

      if (text.startsWith("<!--", open)) {
        var commentEnd = text.indexOf("-->", open + 4);
        index = commentEnd === -1 ? text.length : commentEnd + 3;
        continue;
      }
      if (text.startsWith("<!", open) || text.startsWith("<?", open)) {
        var declarationEnd = text.indexOf(">", open);
        index = declarationEnd === -1 ? text.length : declarationEnd + 1;
        continue;
      }

      var close = text.indexOf(">", open);
      if (close === -1) {
        pushText(text.slice(open));
        break;
      }

      var raw = text.slice(open + 1, close);
      var selfClosing = raw.endsWith("/");
      if (selfClosing) raw = raw.slice(0, -1);

      if (raw.charAt(0) === "/") {
        var closingName = raw.slice(1).trim().toLowerCase();
        for (var depth = stack.length - 1; depth > 0; depth -= 1) {
          if (stack[depth].name === closingName) {
            stack.length = depth;
            break;
          }
        }
        index = close + 1;
        continue;
      }

      var spaceIndex = raw.search(/[\s/]/);
      var tagName = (spaceIndex === -1 ? raw : raw.slice(0, spaceIndex)).toLowerCase();
      var attributeText = spaceIndex === -1 ? "" : raw.slice(spaceIndex);
      if (!tagName) {
        index = close + 1;
        continue;
      }

      var node = createNode("tag", tagName);
      node.attribs = parseAttributes(attributeText);
      node.parent = current();
      current().children.push(node);
      index = close + 1;

      if (VOID_TAGS[tagName] || selfClosing) continue;

      if (RAW_TEXT_TAGS[tagName]) {
        var rawEnd = text.toLowerCase().indexOf("</" + tagName, index);
        var rawContent = rawEnd === -1 ? text.slice(index) : text.slice(index, rawEnd);
        if (rawContent) {
          var rawNode = createNode("text");
          rawNode.value = rawContent;
          rawNode.parent = node;
          node.children.push(rawNode);
        }
        index = rawEnd === -1 ? text.length : text.indexOf(">", rawEnd) + 1 || text.length;
        continue;
      }

      stack.push(node);
    }

    return root;
  }

  // ---------- 选择器 ----------

  function parseSelector(selector) {
    return String(selector).split(",").map(function (group) {
      var tokens = group.trim().split(/\s*>\s*|\s+/).filter(Boolean);
      var combinators = group.trim().match(/>|\s+/g) || [];
      return { tokens: tokens, combinators: combinators.map(function (item) {
        return item.trim() === ">" ? ">" : " ";
      }) };
    });
  }

  function matchCompound(node, compound) {
    if (node.type !== "tag") return false;

    var pattern = /([.#]?[\w-]+|\[[^\]]+\]|:[\w-]+(?:\([^)]*\))?|\*)/g;
    var parts = compound.match(pattern) || [];
    if (parts.length === 0) return true;

    for (var i = 0; i < parts.length; i += 1) {
      var part = parts[i];

      if (part === "*") continue;

      if (part.charAt(0) === "#") {
        if ((node.attribs.id || "") !== part.slice(1)) return false;
        continue;
      }
      if (part.charAt(0) === ".") {
        var classes = (node.attribs.class || "").split(/\s+/);
        if (classes.indexOf(part.slice(1)) === -1) return false;
        continue;
      }
      if (part.charAt(0) === "[") {
        if (!matchAttribute(node, part.slice(1, -1))) return false;
        continue;
      }
      if (part.charAt(0) === ":") {
        if (!matchPseudo(node, part)) return false;
        continue;
      }
      if (node.name !== part.toLowerCase()) return false;
    }
    return true;
  }

  function matchAttribute(node, expression) {
    var match = /^([\w-]+)\s*(?:([~^$*|]?=)\s*(?:"([^"]*)"|'([^']*)'|([^\]]*)))?$/.exec(expression.trim());
    if (!match) return false;

    var name = match[1].toLowerCase();
    var value = node.attribs[name];
    if (match[2] === undefined) return value !== undefined;

    var expected = match[3] !== undefined ? match[3] : match[4] !== undefined ? match[4] : (match[5] || "");
    if (value === undefined) return false;

    switch (match[2]) {
      case "=": return value === expected;
      case "^=": return value.indexOf(expected) === 0;
      case "$=": return value.slice(-expected.length) === expected;
      case "*=": return value.indexOf(expected) !== -1;
      case "~=": return value.split(/\s+/).indexOf(expected) !== -1;
      case "|=": return value === expected || value.indexOf(expected + "-") === 0;
      default: return false;
    }
  }

  function matchPseudo(node, part) {
    var name = part.slice(1).split("(")[0].toLowerCase();
    var argument = part.indexOf("(") === -1 ? "" : part.slice(part.indexOf("(") + 1, -1);

    var siblings = node.parent ? node.parent.children.filter(function (item) { return item.type === "tag"; }) : [node];
    var position = siblings.indexOf(node);

    switch (name) {
      case "first-child": return position === 0;
      case "last-child": return position === siblings.length - 1;
      case "only-child": return siblings.length === 1;
      case "empty": return node.children.every(function (child) {
        return child.type !== "tag" && !child.value.trim();
      });
      case "not": return !matchSelector(node, argument);
      case "contains": return textOf(node).indexOf(argument.replace(/^["']|["']$/g, "")) !== -1;
      case "first": return position === 0;
      case "last": return position === siblings.length - 1;
      case "eq": return position === Number(argument);
      case "nth-child": {
        var nth = Number(argument);
        if (Number.isFinite(nth)) return position === nth - 1;
        if (argument.trim() === "odd") return position % 2 === 0;
        if (argument.trim() === "even") return position % 2 === 1;
        return false;
      }
      default: return true;
    }
  }

  function matchSelector(node, selector) {
    var groups = parseSelector(selector);
    for (var g = 0; g < groups.length; g += 1) {
      if (matchGroup(node, groups[g])) return true;
    }
    return false;
  }

  function matchGroup(node, group) {
    var tokens = group.tokens;
    if (tokens.length === 0) return false;
    if (!matchCompound(node, tokens[tokens.length - 1])) return false;

    var current = node;
    for (var i = tokens.length - 2; i >= 0; i -= 1) {
      var combinator = group.combinators[i] || " ";
      if (combinator === ">") {
        current = current.parent;
        if (!current || !matchCompound(current, tokens[i])) return false;
      } else {
        var ancestor = current.parent;
        var found = false;
        while (ancestor) {
          if (matchCompound(ancestor, tokens[i])) { found = true; break; }
          ancestor = ancestor.parent;
        }
        if (!found) return false;
        current = ancestor;
      }
    }
    return true;
  }

  function collectMatches(root, selector) {
    var groups = parseSelector(selector);
    var matched = [];

    (function walk(node) {
      for (var i = 0; i < node.children.length; i += 1) {
        var child = node.children[i];
        if (child.type === "tag") {
          for (var g = 0; g < groups.length; g += 1) {
            if (matchGroup(child, groups[g])) { matched.push(child); break; }
          }
          walk(child);
        }
      }
    })(root);

    return matched;
  }

  function textOf(node) {
    if (node.type === "text") return node.value;
    var result = "";
    for (var i = 0; i < node.children.length; i += 1) {
      result += textOf(node.children[i]);
    }
    return result;
  }

  function serialize(node) {
    if (node.type === "text") return node.value;
    var html = "<" + node.name;
    Object.keys(node.attribs).forEach(function (name) {
      html += " " + name + '="' + String(node.attribs[name]).replace(/"/g, "&quot;") + '"';
    });
    if (VOID_TAGS[node.name]) return html + ">";
    html += ">";
    for (var i = 0; i < node.children.length; i += 1) {
      html += serialize(node.children[i]);
    }
    return html + "</" + node.name + ">";
  }

  // ---------- cheerio 风格的选择结果 ----------

  function Selection(nodes) {
    this.nodes = nodes || [];
    this.length = this.nodes.length;
    for (var i = 0; i < this.nodes.length; i += 1) {
      this[i] = this.nodes[i];
    }
  }

  Selection.prototype.toArray = function () { return this.nodes.slice(); };
  Selection.prototype.get = function (index) {
    if (index === undefined) return this.nodes.slice();
    return this.nodes[index < 0 ? this.nodes.length + index : index];
  };

  Selection.prototype.each = function (callback) {
    for (var i = 0; i < this.nodes.length; i += 1) {
      callback.call(this.nodes[i], i, this.nodes[i]);
    }
    return this;
  };

  Selection.prototype.map = function (callback) {
    var mapped = [];
    for (var i = 0; i < this.nodes.length; i += 1) {
      var value = callback.call(this.nodes[i], i, this.nodes[i]);
      if (value !== null && value !== undefined) mapped.push(value);
    }
    return new Selection(mapped);
  };

  Selection.prototype.filter = function (target) {
    var nodes = this.nodes;
    if (typeof target === "function") {
      return new Selection(nodes.filter(function (node, index) {
        return target.call(node, index, node);
      }));
    }
    return new Selection(nodes.filter(function (node) {
      return matchSelector(node, target);
    }));
  };

  Selection.prototype.find = function (selector) {
    var found = [];
    this.each(function (_, node) {
      collectMatches(node, selector).forEach(function (item) {
        if (found.indexOf(item) === -1) found.push(item);
      });
    });
    return new Selection(found);
  };

  Selection.prototype.first = function () { return new Selection(this.nodes.slice(0, 1)); };
  Selection.prototype.last = function () { return new Selection(this.nodes.slice(-1)); };
  Selection.prototype.eq = function (index) {
    var target = index < 0 ? this.nodes.length + index : index;
    return new Selection(this.nodes[target] ? [this.nodes[target]] : []);
  };
  Selection.prototype.slice = function (start, end) {
    return new Selection(this.nodes.slice(start, end));
  };

  Selection.prototype.closest = function (selector) {
    var result = [];
    this.each(function (_, node) {
      var current = node;
      while (current) {
        if (current.type === "tag" && matchSelector(current, selector)) {
          if (result.indexOf(current) === -1) result.push(current);
          break;
        }
        current = current.parent;
      }
    });
    return new Selection(result);
  };

  Selection.prototype.parent = function (selector) {
    var parents = this.nodes.map(function (node) { return node.parent; })
      .filter(function (node) { return node && node.type !== "root"; });
    var unique = parents.filter(function (node, index) { return parents.indexOf(node) === index; });
    return new Selection(selector ? unique.filter(function (node) { return matchSelector(node, selector); }) : unique);
  };

  Selection.prototype.children = function (selector) {
    var children = [];
    this.each(function (_, node) {
      node.children.forEach(function (child) {
        if (child.type !== "tag") return;
        if (selector && !matchSelector(child, selector)) return;
        children.push(child);
      });
    });
    return new Selection(children);
  };

  function siblingsOf(node) {
    if (!node.parent) return [];
    return node.parent.children.filter(function (item) {
      return item.type === "tag" && item !== node;
    });
  }

  Selection.prototype.siblings = function (selector) {
    var all = [];
    this.each(function (_, node) {
      siblingsOf(node).forEach(function (item) {
        if (!selector || matchSelector(item, selector)) all.push(item);
      });
    });
    return new Selection(all);
  };

  Selection.prototype.next = function (selector) {
    var result = [];
    this.each(function (_, node) {
      if (!node.parent) return;
      var siblings = node.parent.children;
      for (var i = siblings.indexOf(node) + 1; i < siblings.length; i += 1) {
        if (siblings[i].type !== "tag") continue;
        if (!selector || matchSelector(siblings[i], selector)) result.push(siblings[i]);
        break;
      }
    });
    return new Selection(result);
  };

  Selection.prototype.prev = function (selector) {
    var result = [];
    this.each(function (_, node) {
      if (!node.parent) return;
      var siblings = node.parent.children;
      for (var i = siblings.indexOf(node) - 1; i >= 0; i -= 1) {
        if (siblings[i].type !== "tag") continue;
        if (!selector || matchSelector(siblings[i], selector)) result.push(siblings[i]);
        break;
      }
    });
    return new Selection(result);
  };

  Selection.prototype.has = function (selector) {
    return new Selection(this.nodes.filter(function (node) {
      return collectMatches(node, selector).length > 0;
    }));
  };

  Selection.prototype.not = function (selector) {
    return new Selection(this.nodes.filter(function (node) {
      return !matchSelector(node, selector);
    }));
  };

  Selection.prototype.is = function (selector) {
    if (typeof selector === "function") {
      return this.nodes.some(function (node, index) { return selector.call(node, index, node); });
    }
    return this.nodes.some(function (node) { return matchSelector(node, selector); });
  };

  Selection.prototype.index = function (target) {
    var node = target === undefined ? this.nodes[0] : target;
    if (!node || !node.parent) return -1;
    return node.parent.children.filter(function (item) { return item.type === "tag"; }).indexOf(node);
  };

  Selection.prototype.attr = function (name, value) {
    if (value === undefined) {
      var first = this.nodes[0];
      return first && first.type === "tag" ? first.attribs[name] : undefined;
    }
    return this.each(function (_, node) {
      if (node.type === "tag") node.attribs[name] = String(value);
    });
  };

  Selection.prototype.removeAttr = function (name) {
    return this.each(function (_, node) {
      if (node.type === "tag") delete node.attribs[name];
    });
  };

  Selection.prototype.text = function () {
    var result = "";
    for (var i = 0; i < this.nodes.length; i += 1) {
      result += textOf(this.nodes[i]);
    }
    return result;
  };

  Selection.prototype.html = function () {
    if (this.nodes.length === 0) return null;
    var node = this.nodes[0];
    if (node.type === "text") return node.value;
    return node.children.map(serialize).join("");
  };

  Selection.prototype.val = function () {
    var first = this.nodes[0];
    return first && first.type === "tag" ? first.attribs.value : undefined;
  };

  Selection.prototype.addClass = function (name) {
    return this.each(function (_, node) {
      if (node.type !== "tag") return;
      var classes = (node.attribs.class || "").split(/\s+/).filter(Boolean);
      if (classes.indexOf(name) === -1) classes.push(name);
      node.attribs.class = classes.join(" ");
    });
  };

  Selection.prototype.removeClass = function (name) {
    return this.each(function (_, node) {
      if (node.type !== "tag") return;
      node.attribs.class = (node.attribs.class || "")
        .split(/\s+/)
        .filter(function (item) { return item && item !== name; })
        .join(" ");
    });
  };

  Selection.prototype.hasClass = function (name) {
    var first = this.nodes[0];
    return Boolean(first && first.type === "tag" && (first.attribs.class || "").split(/\s+/).indexOf(name) !== -1);
  };

  Selection.prototype.end = function () { return this; };

  // ---------- 入口 ----------

  function load(html) {
    var root = parseHTML(html);

    function $(input) {
      if (input === undefined || input === null) return new Selection([]);
      if (typeof input === "string") {
        var trimmed = input.trim();
        if (trimmed.charAt(0) === "<") return new Selection(parseHTML(trimmed).children);
        return new Selection(collectMatches(root, trimmed));
      }
      if (input instanceof Selection) return input;
      if (Array.isArray(input)) {
        return new Selection(input.filter(function (item) { return item && item.type; }));
      }
      if (input.type) return new Selection([input]);
      return new Selection([]);
    }

    $.root = function () { return new Selection([root]); };
    $.html = function () { return root.children.map(serialize).join(""); };
    $.parseHTML = parseHTML;
    $.load = load;

    return $;
  }

  globalThis.BreezeHtml = { load: load, parseHTML: parseHTML };
})();
