package com.wetidom.keramika

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Читает текст активного окна ДРУГОГО приложения, чтобы Ада (мини-окно)
 * могла подсказать ответ собеседнику и вообще видеть контекст экрана.
 *
 * Приватность: текст держится ТОЛЬКО в оперативной памяти этого процесса
 * (companion object), на диск не пишется и никуда не отправляется сам по
 * себе — Dart забирает его только в момент отправки сообщения в чат Ады.
 */
class ScreenReaderService : AccessibilityService() {

    companion object {
        @Volatile var latestText: String = ""
            private set
        @Volatile var latestPackage: String = ""
            private set
        @Volatile var latestAt: Long = 0L
            private set
    }

    private var lastCaptureAt = 0L

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        event ?: return
        val pkg = event.packageName?.toString() ?: return

        // Своё окно и клавиатуры не читаем: иначе в снимок попадал бы
        // собственный чат Ады и подсказки клавиатуры — шум вместо пользы.
        if (pkg == packageName) return
        if (pkg.startsWith("com.android.inputmethod") || pkg.contains("inputmethod", ignoreCase = true)) return

        val now = System.currentTimeMillis()
        // Троттлинг: контент-события приходят на каждый чат-кадр мессенджера,
        // обход дерева на каждый из них зря грузит слабый телефон.
        if (now - lastCaptureAt < 600) return
        lastCaptureAt = now

        val root: AccessibilityNodeInfo? =
            if (event.source != null) event.source else rootInActiveWindow
        if (root == null) return
        try {
            val sb = StringBuilder()
            collect(root, sb, 0)
            val text = normalize(sb.toString())
            if (text.isNotEmpty()) {
                latestText = text
                latestPackage = pkg
                latestAt = now
            }
        } catch (_: Exception) {
        } finally {
            try { root.recycle() } catch (_: Exception) {}
        }
    }

    /** Обход дерева нод в глубину: собираем видимый текст и описания. */
    private fun collect(node: AccessibilityNodeInfo?, sb: StringBuilder, depth: Int) {
        if (node == null || depth > 24 || sb.length > 4500) return
        val t = node.text?.toString()?.trim()
        if (!t.isNullOrEmpty() && t != "null") {
            sb.append(t).append('\n')
        } else {
            val d = node.contentDescription?.toString()?.trim()
            if (!d.isNullOrEmpty() && d.length > 1) sb.append(d).append('\n')
        }
        for (i in 0 until node.childCount) {
            try { collect(node.getChild(i), sb, depth + 1) } catch (_: Exception) {}
        }
    }

    /** Схлопываем пустые строки и обрезаем до разумного размера. */
    private fun normalize(raw: String): String {
        val lines = raw.split('\n')
            .map { it.trim() }
            .filter { it.isNotEmpty() }
        val distinct = LinkedHashSet(lines)
        val joined = distinct.joinToString("\n")
        return if (joined.length <= 4000) joined else joined.substring(0, 4000)
    }

    override fun onInterrupt() {}

    override fun onServiceConnected() {
        super.onServiceConnected()
        // Мусор от предыдущей сессии сервиса не должен жить вечно.
        latestText = ""
        latestPackage = ""
        latestAt = 0L
    }
}
