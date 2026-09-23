# Resources

- `LangModel.bin` — character-trigram statistics for Thai and English used by Convert Layout.
  Rebuild with `tools/build-langmodel.py <thai word-freq> <english word-freq> Resources/LangModel.bin`.
  - Thai: `tnc_freq.txt` from [PyThaiNLP](https://github.com/PyThaiNLP/pythainlp) (Thai National Corpus word frequencies, Apache-2.0)
  - English: `count_1w.txt` from [Peter Norvig](https://norvig.com/ngrams/) (Google Web Trillion Word Corpus)
