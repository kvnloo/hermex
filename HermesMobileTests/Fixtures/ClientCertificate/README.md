# XCTest client identity

`test-client.p12` is a generated, self-signed identity with a throwaway key.
Do not use it outside tests. The test passphrase deliberately includes
one leading and one trailing space. The separate PEM files are not retained.

Generate a replacement with OpenSSL 3:

```sh
openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
  -subj '/CN=Hermex XCTest Client' -addext 'extendedKeyUsage=clientAuth' \
  -keyout key.pem -out cert.pem
openssl pkcs12 -export -inkey key.pem -in cert.pem -out test-client.p12 \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
  -passout 'pass: test-only '
```
