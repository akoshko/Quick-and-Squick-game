// Экран загрузки веб-версии: вместо картинки Godot (#status-splash) — видео логотипа.
// Подключается через html/head_include пресета Web; файлы из web/ копируют рядом с экспортом deploy-скрипты.
// Видео играет один раз и остаётся на последнем кадре (полный логотип), пока грузится игра.
document.addEventListener("DOMContentLoaded", function () {
	var splash = document.getElementById("status-splash");
	if (!splash) return;
	var video = document.createElement("video");
	video.id = "status-logo";
	video.src = "logo.mp4";
	video.poster = "logo.png";  // полный логотип, если видео не запустится
	video.muted = true;        // без звука браузеры разрешают автозапуск (и на iPhone)
	video.autoplay = true;
	video.playsInline = true;
	video.setAttribute("muted", "");
	video.setAttribute("playsinline", "");
	video.disablePictureInPicture = true;
	Object.assign(video.style, {
		width: "min(90vw, 640px)",
		maxHeight: "70vh",
		objectFit: "contain",
		imageRendering: "pixelated",
		pointerEvents: "none",
	});
	splash.replaceWith(video);
	var play = video.play();
	if (play && play.catch) play.catch(function () {});  // автозапуск запрещён — виден постер
});
