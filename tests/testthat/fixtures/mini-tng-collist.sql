CREATE TABLE `tng_people` (
  `personID` varchar(22) NOT NULL,
  `firstname` varchar(127) NOT NULL,
  `lastname` varchar(127) NOT NULL,
  `birthdatetr` date NOT NULL,
  `deathdatetr` date NOT NULL,
  `sex` varchar(25) NOT NULL,
  `living` tinyint NOT NULL,
  `private` tinyint NOT NULL
) ENGINE=InnoDB;
INSERT INTO `tng_people` (`personID`, `firstname`, `lastname`, `birthdatetr`, `deathdatetr`, `sex`, `living`, `private`) VALUES
('I1', 'Conrad', 'Reventlow', '1644-04-21', '1708-07-21', 'M', 0, 0),
('I2', 'Sophie', 'von Ahlefeldt', '1670-01-01', '0000-00-00', 'F', 0, 0);
