// Веб-страница игры: заголовок вкладки и логотип на экране загрузки.
// Подключается через html/head_include пресета Web; файлы из web/ копируют рядом с экспортом deploy-скрипты.

// Заголовок вкладки. Godot при старте ставит document.title = application/config/name; само имя
// проекта не меняем: от него зависит папка user:// (сохранённый персонаж игроков в браузере).
(function () {
	var TITLE = "TulaHack 2026";
	var native = Object.getOwnPropertyDescriptor(Document.prototype, "title");
	native.set.call(document, TITLE);
	Object.defineProperty(document, "title", {
		configurable: true,
		get: function () { return native.get.call(document); },
		set: function () {},  // движок не перезапишет название
	});
})();

// Экран загрузки: вместо картинки Godot (#status-splash) — пиксельный GIF логотипа.
document.addEventListener("DOMContentLoaded", function () {
	var splash = document.getElementById("status-splash");
	if (!splash) return;
	var logo = document.createElement("img");
	logo.id = "status-logo";
	logo.src = "logo.gif";
	logo.className = "pixel";
	logo.width = 256;
	logo.height = 256;
	logo.alt = "";
	splash.replaceWith(logo);
});

var style = document.createElement("style");
style.textContent =
	".pixel { image-rendering: pixelated; image-rendering: crisp-edges; object-fit: contain; }";
document.head.appendChild(style);
