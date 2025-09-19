DROP TABLE IF EXISTS `jbc`;
CREATE TABLE `jbc` (
  `styiuid` char(100) NOT NULL,
  `stydir` varchar(255) NULL,
  `compressed` enum('y','n') DEFAULT 'n',
  `error` enum('y','n') DEFAULT 'n',
  `comment` varchar(64) DEFAULT '' NULL,
  INDEX `xcompressed` (`compressed`),
  INDEX `xerror` (`error`),
  PRIMARY KEY(styiuid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
