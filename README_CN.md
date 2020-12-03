Vimium - 骇客的浏览器
=============================

[![Build Status](https://travis-ci.org/philc/vimium.svg?branch=master)](https://travis-ci.org/philc/vimium)

Vimium是一个遵循vim编辑器精神，基于键盘操作进行导航和网页控制的浏览器插件。

__安装指南:__

通过
[Chrome 应用商店](https://chrome.google.com/extensions/detail/dbepggeogbaibhgnhhndojpepiihcmeb) 或 [Firefox 应用商店](https://addons.mozilla.org/en-GB/firefox/addon/vimium-ff/).

如果想要通过源码安装，可以看 [这里](CONTRIBUTING.md#installing-from-source).

Vimium的设置界面可以通过帮助界面（键入“？”）的链接进入或者通过浏览器中的插件界面，例如 Chrome (`chrome://extensions`) 或 Firefox (`about:addons`).

按键设置
-----------------
自定义设置如 `<c-x>`, `<m-x>`, 和 `<a-x>` 指的是 ctrl+x, meta+x, 和 alt+x. 对于 shift+x 和 ctrl-shift-x 输入 `X` 和 `<c-X>`就好了. 来看看下一部分如何自定义自己的按键.

一旦你安装了Vimium就可以通过 `?` 键来查询下面的按键设置.

操作当前界面:

    ?       展示键位设置
    h       向左滚动
    j       向下滚动
    k       向上滚动
    l       向右滚动
    gg      滚动到页面顶端
    G       滚动到页面底端
    d       向下滚动半页
    u       向上滚动半页
    f       在新页面中打开页面中链接（跳转到新页面）
    F       在新页面中打开页面中链接（不自动跳转）
    r       刷新
    gs      查看源代码
    i       进入“插入模式” -- 所有的按键都会被忽略，直到你按下了esc退出（开发人员的小幽默？）
    yy      把当前页面的地址复制到剪切板
    yf      把页面中超链接复制到剪切板
    gf      循环滚动到下一个frame标签
    gF      聚焦到主要或最上面的frame标签

操作新页面:

    o       打开地址、书签、历史记录查询窗口（当前网页被刷新）
    O       打开地址、书签、历史记录查询窗口（新打开一个网页）
    b       打开书签查询窗口（当前网页被刷新）
    B       打开书签查询窗口（新打开一个网页）

使用查找功能:

    /       进入查询模式
              -- 输入你要查询的内容，按下回车搜索或者按下 Esc 来退出
    n       循环滚动到下一个查询结果
    N       循环滚动到上一个查询结果

更高级的使用方式，请查询wiki上的 [正常的表述](https://github.com/philc/vimium/wiki/Find-Mode).

历史操作:

    H       后退
    L       前进

处理标签页:

    J, gT   切换到左边的标签页
    K, gt   切换到右边的标签页
    g0      切换到第一个标签页
    g$      切换到最后的标签页
    ^       切换到刚才访问的标签页
    t       新建一个标签页
    yt      复制一个当前标签页
    x       关闭当前标签页
    X       找回刚刚关闭的标签页
    T       在已经打开的标签页中搜索
    W       把当前页转移到一个新的窗口
    <a-p>   固定当前标签页

使用标记:

    ma, mA  设定一个标记名为"a" (全局标记 "A")
    `a, `A  跳到一个标记名为"a" (全局标记 "A")
    ``      跳到刚才跳到的地方
              -- 也就是说跳到刚才的 gg, G, n, N, / 或者 `a

附加的高级浏览器操作:

    ]], [[  跳到标签为'next' 或 '>'的地方 ('previous' or '<')
              - 对于访问有页码的网页来说很有用
    <a-f>   在新标签页中打开多个链接
    gi      聚焦到第一个或第n个当前页面上的文本输入框
    gu      访问当前URL的上一目录
    gU      访问当前URL的根目录
    ge      编辑当前的URL
    gE      编辑当前URL并在新页面打开
    zH      滚动到最左边
    zL      滚动到最右边
    v       进入可视化模式; 使用 p/P 来复制并访问，使用 y 来复制
    V       进入可视化线模式

Vimium也支持数字操作，例如, 输入 `5t` 将会一次性打开五个新标签 `<Esc>` (或者
`<c-[>`) 将会清空任何未完成的操作，比如查找模式之类的
还有一些高级的操作没有讲到，可以访问帮助界面来浏览 (按下 `?`) 完整的列表.

自定义按键布局
-------------------

你可以在设置页面的"Custom key mappings"来消除或重新绑定默认的键位设置 

每一行设置应写类似如下的命令:

- `map 按键 指令`: 绑定一个按键到Vimium，并且覆盖默认设置 (如果有的话).
- `unmap 按键`: 取消绑定一个按键，并且会覆盖默认设置 (如果有的话).
- `unmapAll`: 取消绑定所有的按键，当你要完全取消默认设定时，会比较有效.

例子:

- `map <c-d> scrollPageDown` 绑定 ctrl+d 为向下滚动页面. Chrome 的默认快捷键会被抑制.
- `map r reload` 把 r 绑定为刷新页面
- `unmap <c-d>` 取消 ctrl+d 的键位绑定并且恢复 Chrome 的默认快捷键.
- `unmap r` 取消 r 的键位绑定.

在设置页面的键位绑定盒子附近可以通过"Show available commands"链接来找到可用的键位设置.命令名出现在描述的右侧.

你可以用 `"` 或 `#` 给键位绑定写点注释.

下面的特殊键位可以在键位绑定中使用:

- `<c-*>`, `<a-*>`, `<m-*>` 代表了 ctrl, alt, 以及 meta (Mac上的命令键) 加上 `*`所代表的键.
- `<left>`, `<right>`, `<up>`, `<down>` 代表了方向键.
- `<f1>` 到 `<f12>` 代表了函数或功能键.
- `<space>` 代表了空格键.
- `<tab>`, `<enter>`, `<delete>`, `<backspace>`, `<insert>`, `<home>` 以及 `<end>` 代表了对应的导航键.

Shifts会被自动检测到, 例如, `<c-&>` 代表的是英文键盘上的 ctrl+shift+7. 

更多的文档
------------------
还有很多更高级的用法写在了
[Vimium's GitHub wiki](https://github.com/philc/vimium/wiki) 上. 也可以看看这个 [FAQ](https://github.com/philc/vimium/wiki/FAQ).

支持
------------
访问 [CONTRIBUTING.md](CONTRIBUTING.md) 来看支持内容

发布日志
-------------

访问 [CHANGELOG](CHANGELOG.md) 来看每次主要更新了什么

许可证
-------
Copyright (c) Phil Crosby, Ilya Sukhar. 看 [MIT-LICENSE.txt](MIT-LICENSE.txt) 来获得更多信息.
