# This file is maintained automatically by "tofu init".
# Manual edits may be lost in future updates.

provider "registry.opentofu.org/gavinbunney/kubectl" {
  version     = "1.19.0"
  constraints = "~> 1.19"
  hashes = [
    "h1:EL1HfCDfY/pabIJ2kXuppTvqhgY9hfLu2o4TonJheT8=",
    "h1:quymfa/OKEfWI5JXFEwGbUY2aAy0vet3rA9JWJam+3k=",
    "zh:1dec8766336ac5b00b3d8f62e3fff6390f5f60699c9299920fc9861a76f00c71",
    "zh:43f101b56b58d7fead6a511728b4e09f7c41dc2e3963f59cf1c146c4767c6cb7",
    "zh:4c4fbaa44f60e722f25cc05ee11dfaec282893c5c0ffa27bc88c382dbfbaa35c",
    "zh:51dd23238b7b677b8a1abbfcc7deec53ffa5ec79e58e3b54d6be334d3d01bc0e",
    "zh:5afc2ebc75b9d708730dbabdc8f94dd559d7f2fc5a31c5101358bd8d016916ba",
    "zh:6be6e72d4663776390a82a37e34f7359f726d0120df622f4a2b46619338a168e",
    "zh:72642d5fcf1e3febb6e5d4ae7b592bb9ff3cb220af041dbda893588e4bf30c0c",
    "zh:9b12af85486a96aedd8d7984b0ff811a4b42e3d88dad1a3fb4c0b580d04fa425",
    "zh:a1da03e3239867b35812ee031a1060fed6e8d8e458e2eaca48b5dd51b35f56f7",
    "zh:b98b6a6728fe277fcd133bdfa7237bd733eae233f09653523f14460f608f8ba2",
    "zh:bb8b071d0437f4767695c6158a3cb70df9f52e377c67019971d888b99147511f",
    "zh:dc89ce4b63bfef708ec29c17e85ad0232a1794336dc54dd88c3ba0b77e764f71",
    "zh:dd7dd18f1f8218c6cd19592288fde32dccc743cde05b9feeb2883f37c2ff4b4e",
    "zh:ec4bd5ab3872dedb39fe528319b4bba609306e12ee90971495f109e142d66310",
    "zh:f610ead42f724c82f5463e0e71fa735a11ffb6101880665d93f48b4a67b9ad82",
  ]
}

provider "registry.opentofu.org/hashicorp/external" {
  version = "2.3.5"
  hashes = [
    "h1:3VK0DggxYvOG1o+2o+araLMi3JQ/wJsJku0+ytaqtLA=",
    "h1:VsIY+hWGvWHaGvGTSKZslY13lPeAtSTxfZRPbpLMMhs=",
    "zh:1fb9aca1f068374a09d438dba84c9d8ba5915d24934a72b6ef66ef6818329151",
    "zh:3eab30e4fcc76369deffb185b4d225999fc82d2eaaa6484d3b3164a4ed0f7c49",
    "zh:4f8b7a4832a68080f0bf4f155b56a691832d8a91ce8096dac0f13a90081abc50",
    "zh:5ff1935612db62e48e4fe6cfb83dfac401b506a5b7b38342217616fbcab70ce0",
    "zh:993192234d327ec86726041eb6d1efb001e41f32e4518ad8b9b162130b65ee9a",
    "zh:ce445e68282a2c4b2d1f994a2730406df4ea47914c0932fb4a7eb040a7ec7061",
    "zh:e305e17216840c54194141fb852839c2cedd6b41abd70cf8d606d6e88ed40e64",
    "zh:edba65fb241d663c09aa2cbf75026c840e963d5195f27000f216829e49811437",
    "zh:f306cc6f6ec9beaf75bdcefaadb7b77af320b1f9b56d8f50df5ebd2189a93148",
    "zh:fb2ff9e1f86796fda87e1f122d40568912a904da51d477461b850d81a0105f3d",
  ]
}

provider "registry.opentofu.org/hashicorp/helm" {
  version     = "3.1.1"
  constraints = "~> 3.1"
  hashes = [
    "h1:I0TSwVK/TX2Ib2sVKa6d4P0YVl3lnmAqgAHuJBaKpqw=",
    "h1:brfn5YltnzexsfqpWKw+5gS9U/m77e0An3hZQamlEZk=",
    "zh:09b38905e234c2e0b185332819614224660050b7e4b25e9e858b593ab01adafe",
    "zh:09fed1b19b8bcded169fb76304e06c5b1216d5ceba92948c23384f34ddbf1fac",
    "zh:2e0af220f3fe79048d82f6de91752ba9929c215819d3de4f82ccb473bcd9e5df",
    "zh:5fe8657cbf6aca769b9565a4fb4605d7b441c2c558d915b067c0adf6f77c58d4",
    "zh:713943f797be3a4c6fc6bb5f1306c4f74762bfaa663f98fd8b4c49d28ee54ecf",
    "zh:b426458c0bbad64f9000c11af7e74a24ce9e0adb3037c05dadf80c0c3e757931",
    "zh:c0664866280a42156484a48f6c461d0ddb2d212da9b6e930c721ef577ab75270",
    "zh:e4f9d0ebb70d63d8ac3ccee00a4d8cdb15b97aaa390f95ed65921e9d0f65bfa0",
    "zh:f6fe7ecfafc344f4e6aecacf5ae12ac73b94389b9679dcd0f04fc5ff45bdc066",
  ]
}

provider "registry.opentofu.org/hashicorp/kubernetes" {
  version     = "3.0.1"
  constraints = "~> 3.0"
  hashes = [
    "h1:41qY8vMBCsZLvpJZoiMrofr3UiOm2p1If7UPti/AHPI=",
    "h1:e0dSpTDhKjin6KYIwLWTR+AHVC7wWlU3VfIx27n1bec=",
    "zh:0a6aff192781cfd062efe814d87ec21c84273005a685c818fb3c771ec9fd7051",
    "zh:129f10760e8c727f7b593111e0026aa36aeb28c98f6500c749007aabba402332",
    "zh:4a0995010f32949b1fbe580db15e76c73ba15aa265f73a7e535addd15dfade0d",
    "zh:8b518be59029e8f0ad0767dbbd87f169ac6c906e50636314f8a5ff3c952f0ad5",
    "zh:a2f1c113ae07dc5da8410d7a93b7e9ad24c3f17db357f090e6d68b41ed52e616",
    "zh:b1d3604a2f545beae0965305d7bca821076cc9127fc34a77eef01c2d0cf916d2",
    "zh:c2f2d371018d77affce46fee8b9a9ff0d27c4d5c3c64f8bce654e7c8d3305dc1",
    "zh:c7cf958fb9bb429086ff1d371a4b824ec601ec0913dddaf85cd2e38d73ca7ec0",
    "zh:f7753278388598c8e27140c5700e5699a0131926df8dad362f86ad67c36585ea",
  ]
}

provider "registry.opentofu.org/hashicorp/local" {
  version     = "2.8.0"
  constraints = "~> 2.6"
  hashes = [
    "h1:X/bA7cd5DhdNmHOS9JvhIUGJ8wv3lHxQ5RIXubyDKNc=",
    "h1:XybiBEkq4bcztcMIb1YZJo33oFgx40i63lhPG0TmiRU=",
    "zh:0aaa04a29638eb2f84145aeec030ed4b469980c51f60f7f72ddbd705e0c9ceea",
    "zh:1d2f29cdfdc607f6b6b641e8bc7b00c73ac29f572ae8aa9b18fd068c107a7315",
    "zh:3cba45610ee2abbbe73694f5604d6628b036cee35d5e77f2353043088e950ff2",
    "zh:435fca586d45fcf200974d90962fa4cffaf761bad4c774bd34d1b92463a9887f",
    "zh:662748c6ad1e3d64500b70d3e2ccd5d2b04471dfd687c524f15bf3dbe68954a2",
    "zh:68f3a6dd1a6ddb7f4935ce894861740dd39f2202c5ba4aebc217c742e426a80c",
    "zh:75267c8b3d693125e7c6814058fef6189e0dae6c44c47cd63109d919b35e665e",
    "zh:88a1e4c13876774fae1ae20129a328cb6031e3aca00435bc7899e4038c2f43f7",
    "zh:8b8bffe1adeedf13a5c4af7b208b47ca5d4cac09ff51028962a3465e26830fef",
    "zh:b99ddf3c8fb730e4a9e4ded4c5706bcca3b7b8d2f2ea458f01a4dda26c78fdd3",
    "zh:d08174d23b2fe4a53b7f81f32ff0089e6ca76162a9de3c411deff7eb45d3d677",
    "zh:d220cd9f2ea3426ab5e2c528700c15d8fbcd4254496a84945b38885c6e4b18d3",
    "zh:de1e7f2ec372aaf717a26017e25f24bc22cbfc0e1691711484df26d828c6f8a0",
    "zh:e1b7c0ccaea53904b999a0d3993e86b97766eaa3698040c0bbe14b453cefd91a",
    "zh:e7eacd0e7a223fee0ac1fee5f032199219fde3cf0db43ad9d31b75a122f440ae",
  ]
}

provider "registry.opentofu.org/hashicorp/null" {
  version     = "3.2.4"
  constraints = "~> 3.2"
  hashes = [
    "h1:8ghdTVY6mALCeMuACnbrTmPaEzgamIYlgvunvqI2ZSY=",
    "h1:i+WKhUHL2REY5EGmiHjfUljJB8UKZ9QdhdM5uTeUhC4=",
    "zh:1769783386610bed8bb1e861a119fe25058be41895e3996d9216dd6bb8a7aee3",
    "zh:32c62a9387ad0b861b5262b41c5e9ed6e940eda729c2a0e58100e6629af27ddb",
    "zh:339bf8c2f9733fce068eb6d5612701144c752425cebeafab36563a16be460fb2",
    "zh:36731f23343aee12a7e078067a98644c0126714c4fe9ac930eecb0f2361788c4",
    "zh:3d106c7e32a929e2843f732625a582e562ff09120021e510a51a6f5d01175b8d",
    "zh:74bcb3567708171ad83b234b92c9d63ab441ef882b770b0210c2b14fdbe3b1b6",
    "zh:90b55bdbffa35df9204282251059e62c178b0ac7035958b93a647839643c0072",
    "zh:ae24c0e5adc692b8f94cb23a000f91a316070fdc19418578dcf2134ff57cf447",
    "zh:b5c10d4ad860c4c21273203d1de6d2f0286845edf1c64319fa2362df526b5f58",
    "zh:e05bbd88e82e1d6234988c85db62fd66f11502645838fff594a2ec25352ecd80",
  ]
}

provider "registry.opentofu.org/hashicorp/random" {
  version     = "3.8.1"
  constraints = "~> 3.7"
  hashes = [
    "h1:LsYuJLZcYl1RiH7Hd3w90Ra5+k5cNqfdRUQXItkTI8Y=",
    "h1:tZP70yQDl6mKnTsDtx6tS6GReVb1lgb7WnlIIneXsHY=",
    "zh:25c458c7c676f15705e872202dad7dcd0982e4a48e7ea1800afa5fc64e77f4c8",
    "zh:2edeaf6f1b20435b2f81855ad98a2e70956d473be9e52a5fdf57ccd0098ba476",
    "zh:44becb9d5f75d55e36dfed0c5beabaf4c92e0a2bc61a3814d698271c646d48e7",
    "zh:7699032612c3b16cc69928add8973de47b10ce81b1141f30644a0e8a895b5cd3",
    "zh:86d07aa98d17703de9fbf402c89590dc1e01dbe5671dd6bc5e487eb8fe87eee0",
    "zh:8c411c77b8390a49a8a1bc9f176529e6b32369dd33a723606c8533e5ca4d68c1",
    "zh:a5ecc8255a612652a56b28149994985e2c4dc046e5d34d416d47fa7767f5c28f",
    "zh:aea3fe1a5669b932eda9c5c72e5f327db8da707fe514aaca0d0ef60cb24892f9",
    "zh:f56e26e6977f755d7ae56fa6320af96ecf4bb09580d47cb481efbf27f1c5afff",
  ]
}

provider "registry.opentofu.org/hashicorp/tls" {
  version     = "4.2.1"
  constraints = "~> 4.1"
  hashes = [
    "h1:RZDD1y8qrxf7+gdnfFcGP0G6GDe/kv4zNDNdg1HpuSQ=",
    "h1:ZilRQg3gaNxvWpwnrjV3ZyU4dXI0yQfgsxu2swX9E14=",
    "zh:0435b85c1aa6ac9892e88d99eaae0b1712764b236bf469c114c6ff4377b113d6",
    "zh:3413d6c61a6a1db2466200832e1d86b2992b81866683b1b946e7e25d99e8daf9",
    "zh:4e7610d4c05fee00994b851bc5ade704ae103d56f28b84dedae7ccab2148cc3f",
    "zh:5d7d29342992c202f748ff72dcaa1fa483d692855e57b87b743162eaf12b729a",
    "zh:7db84d143330fcc1f6f2e79b9c7cc74fdb4ddfe78d10318d060723d6affb8a5c",
    "zh:b7fb825fd0eccf0ea9afb46627d2ec217d2d99a5532de8bcbdfaa0992d0248e2",
    "zh:cb8ca2de5f7367d987a23f88c76d80480bcc49da8bdc3fd24dd9b19d3428d72d",
    "zh:eb88588123dd53175463856d4e2323fb0da44bdcf710ec34f2cad6737475638b",
    "zh:f92baceb82d3a1e5b6a34a29c605b54cae8c6b09ea1fffb0af4d036337036a8f",
  ]
}

provider "registry.opentofu.org/tehcyx/kind" {
  version     = "0.11.0"
  constraints = "~> 0.11.0"
  hashes = [
    "h1:+Q1amcdec50yH5urYvojIkQZdCXJwV/6wG7rFpIgfaY=",
    "h1:5YkI2sD2PSilFvCvUL2dtyRkrTvxO7PLOgbIZXMbelA=",
    "zh:10cf5f11ed1b24bcc2a64ddfe529dbe240ac72c075100039eb8a182abd5a25d8",
    "zh:1c652afcea840545f9e21cf42369560966eafe52986d578c31a35247624442bf",
    "zh:8ed94e1387970e7b885c7a68579b17a662d769d04dd3a0917d6c795741d0b97c",
    "zh:97e3591b821b8a7cd1d0bc6322c1cbeed882ca26ff357cdcfab8dc0b17279090",
    "zh:d5789b07c0a76d086d19acf948246875cb20bea0826a164f4f2c36b8fe527385",
    "zh:e5a1117080f6b51e836bf41576e62ee1ea738a5d5fb2f5b0fccb25c942dfb557",
  ]
}
