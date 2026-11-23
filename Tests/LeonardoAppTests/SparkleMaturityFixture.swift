import Foundation

/// Public sign_update assertion over the published 0.1.571 archive and signed resource seal.
/// Verification fixture only; no private key and no remote publication.
enum SparkleMaturityFixture {
    static let data = Data(#"""
{
  "payload": "eyJhcmNoaXZlU0hBMjU2IjoiMjRmNzY4OTk3M2I4Y2IxOTQ3M2E4MWZiYTkxOWJmOTU5MzEzNmRjY2UxOTgwYTgyODI0NWQzMmY5Yjc3ZThiNiIsImJ1aWxkIjoiNTcxIiwiY2hhbm5lbCI6InN0YWJsZSIsImV4ZWN1dGFibGVTSEEyNTYiOiI0OGQ1OTcyNWQ2YWRkMDc3ZDE5YjdlNGM1ZTg0ZmI1NzI0M2ZkOTJmNzllZjM2NzRhODk0MzUxNmNmMGY1MGMxIiwicmVwb3NpdG9yeSI6IlBpbmVkYVRlYy1FVS9MZW9uYXJkb01EIiwicmVzb3VyY2VTZWFsU0hBMjU2IjoiOGRkODQ5OTYwNDZmYzc0NTM3Y2U0YzhlMTY0ZDU2YTE3NTgxZDQxMDQzY2UxOTUwNzRmZWNjYmI5YTVmNTUwNCIsInNjaGVtYSI6MSwidmVyc2lvbiI6IjAuMS41NzEifQ==",
  "signature": "yjkudYLkU4lf+JTOPCyiKGCYNdRlCcH0fyoASnbitqaHiPve1NjUn4D5dUcuFaiL9p1yFh9ihUtpUkKwkhnUDA=="
}
"""#.utf8)
}
