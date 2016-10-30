# Ruby Fonttool

## 何これ？
これは、CFF形式のフォントファイルをRubyが読める形式に変換するプログラムです。

## どう使うの？
```bash
$ git clone https://github.com/pixie-grasper/ruby-fonttool.git
```

すれば

```bash
$ ./cff2rb Inconsolata.cff -o Inconsolata.rb
```

みたいな感じで使えます。

## 何が出来るの？
CFF形式のファイルを読めるだけです。
付属のサンプルプログラム(rb2svg)を走らせればSVG形式に変換することが出来ます。

## 依存関係
- ruby ~> 1.9
- no gems, no fontforge, et cetra.

## Authors
- pixie-grasper

## License
The MIT License
