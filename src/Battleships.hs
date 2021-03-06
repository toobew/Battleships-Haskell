module Battleship where

import DataTypes
import RunGame
import Data.List
import System.Random
import Test.QuickCheck

instance Arbitrary Board where
  arbitrary = do
    n <- choose (0,4)
    m <- arbitrary
    shipTypes <- vectorOf n $ elements [Destroyer, Submarine, Cruiser, Battleship, Carrier]
    return (foldr (addShipRandom (mkStdGen m)) emptyBoard shipTypes)

instance Arbitrary Orientation where
  arbitrary = oneof [return Vertical, return Horizontal]

instance Arbitrary ShipType where
  arbitrary = oneof [return Destroyer, return Submarine, return Cruiser, return Battleship, return Carrier]

instance Arbitrary Ship where
  arbitrary = do
    orientation <- arbitrary
    shipType <- arbitrary
    return (Ship orientation shipType)

instance Arbitrary Position where
  arbitrary = do
    x <- choose (0,9)
    y <- choose (0,9)
    return (Position x y)

impl = Interface
   { iNewGame = newGame
   , iPrintGame = printGame
   , iWinnerIs = winnerIs
   , iGameOver = gameOver
   , iShoot = shoot
   , iComputerShoot = computerShoot
   }

-- starts the game
main :: IO ()
main = runGame impl

-- new game
newGame :: StdGen -> Game
newGame g = createGame g level
    where level = Level [(Carrier,1),(Battleship,1),(Cruiser,2),(Submarine,3),(Destroyer,2)]

-- creates a game where ships according to Level have been randomly positioned
createGame :: StdGen -> Level -> Game
createGame g lvl = Game (createBoard g lvl emptyBoard) (createBoard g lvl emptyBoard)
    where createBoard :: StdGen -> Level -> Board -> Board
          createBoard _ (Level []) b = b
          createBoard g (Level ((s,n):xs)) b = createBoard g (Level xs) (createBoard' g s n b)
              where createBoard' :: StdGen -> ShipType -> Int -> Board -> Board
                    createBoard' _ _ 0 b = b
                    createBoard' g s n b = createBoard' g1 s (n-1) (addShipRandom g1 s b)
                        where (r,g1) = random g :: (Int,StdGen)

-- Returns an empty board
emptyBoard :: Board
emptyBoard = Board (replicate 10 (replicate 10 Water))

-- Adds a ship at a random position on the board
addShipRandom :: StdGen -> ShipType -> Board -> Board
addShipRandom g s b = addShipRandom' g b s (getRandomOrientation g)
  where addShipRandom' :: StdGen -> Board -> ShipType -> Orientation -> Board
        addShipRandom' g b s o | isShipAddOk b ship pos = addShip b ship pos
                               | otherwise = addShipRandom' g3 b s o
            where ship = Ship o s
                  pos = Position x y
                  (x,g2) = randomR (0, maxX ship) g
                  (y,g3) = randomR (1, maxY ship) g2
                  -- returns maximum possible x-coordinate to add ship at
                  maxX :: Ship -> Int
                  maxX (Ship Vertical _) = 9
                  maxX (Ship Horizontal s) = 10 - shipSize s
                  -- returns maximum possible y-coordinate to add ship at
                  maxY :: Ship -> Int
                  maxY (Ship Vertical s) = 10 - shipSize s
                  maxY (Ship Horizontal _) = 9

-- returns a random orientation, Horizontal or Vertical
getRandomOrientation :: StdGen -> Orientation
getRandomOrientation g | getRandom g ==0 = Horizontal
    where getRandom :: StdGen -> Int
          getRandom g = o
              where (o,g2) = randomR (0, 1) g
getRandomOrientation g = Vertical

-- Checks whether the given position is a valid position to place a ship in.
isShipAddOk :: Board -> Ship -> Position -> Bool
isShipAddOk (Board matrix) (Ship ori shipT) (Position x y) | ori == Horizontal =
               isShipAddOk' x (shipSize shipT) (matrix !! y)
                                                           | ori == Vertical =
               isShipAddOk' y (shipSize shipT) (map (head) $ map (drop x) matrix)
       where
          isShipAddOk' :: Int -> Int -> [Block] -> Bool
          isShipAddOk' x sSize list | (x+sSize) >= 10 = False
                                    | otherwise = and $ map (==Water) (take sSize $ drop x list)

-- Blindly adds blocks of type Block to a board according to an array of positions.
addBlocks :: Board -> [Position] -> Block -> Board
addBlocks board [] _ = board
addBlocks board (x:xs) block | isValid x = addBlocks (setBlock board x block) xs block
                             | otherwise = addBlocks board xs block

-- Takes a ship and the upper left position of the ship and returns
-- an array of all the ShipPart positions.
getShipPositions :: Ship -> Position -> [Position]
getShipPositions (Ship Horizontal shipType) (Position x y) = intsToPos (map (+x) [0..(shipSize shipType - 1)]) (replicate (shipSize shipType) y)
getShipPositions (Ship Vertical shipType) (Position x y) = intsToPos (replicate (shipSize shipType) x) (map (+y) [0..(shipSize shipType - 1)])

-- takes to list of Ints, x- and y coordinates, and returns a list of positions
intsToPos :: [Int] -> [Int] -> [Position]
intsToPos [] _ = []
intsToPos _ [] = []
intsToPos (x:xs) (y:ys) = Position x y : intsToPos xs ys

-- Adds a ship at the given position in the ships orientation
-- where the position is the upper most left part of the ship.
addShip :: Board -> Ship -> Position -> Board
addShip b (Ship o s) pos = addBlocks (addBlocks b shipPositions ShipPart) swellPositions Swell
  where shipPositions = getShipPositions (Ship o s) pos
        swellPositions = getSwellPositions shipPositions o

-- takes positions of a ship and its orientation, returns a list of positions
-- were Swell should be added
getSwellPositions :: [Position] -> Orientation -> [Position]
getSwellPositions pos o = getSides pos o ++ getCorners pos o
    where -- returns positions of Swell on side of ship
          getSides :: [Position] -> Orientation -> [Position]
          getSides pos Horizontal = moveShip pos 0 (-1) ++ moveShip pos 0 1
          getSides pos Vertical = moveShip pos (-1) 0 ++ moveShip pos 1 0
          moveShip :: [Position] -> Int -> Int -> [Position]
          moveShip [] _ _ = []
          moveShip (Position x y : as) dx dy = Position (x+dx) (y+dy) : moveShip as dx dy
          -- returns positions of Swell in "corner" of ship
          getCorners :: [Position] -> Orientation -> [Position]
          getCorners pos Horizontal = getCorners' (head pos) Horizontal (-1) 0 ++ getCorners' (last pos) Horizontal 1 0
          getCorners pos Vertical = getCorners' (head pos) Vertical 0 (-1) ++ getCorners' (last pos) Vertical 0 1
          getCorners' :: Position -> Orientation -> Int -> Int -> [Position]
          getCorners' (Position x y) o dx dy = makeThree (Position (x+dx) (y+dy)) o
              where makeThree :: Position -> Orientation -> [Position]
                    makeThree (Position x y) Vertical = [Position (x-1) y] ++ [Position x y] ++ [Position (x+1) y]
                    makeThree (Position x y) Horizontal = [Position x (y-1)] ++ [Position x y] ++ [Position x (y+1)]

-- Tests if addShip really adds a ship at the given positon by first counting
-- the number of ShipParts on the board before and after adding to make sure that
-- the correct number of ShipParts were added and then checking so that there is
-- a ShipPart at every position of the added ship.
prop_addShip :: Board -> Ship -> Position -> Bool
prop_addShip board (Ship ori shipType) pos | isShipAddOk board (Ship ori shipType) pos =
  (nbrOf board ShipPart) + shipSize shipType == (nbrOf (addShip board (Ship ori shipType) pos) ShipPart)
  && prop_addShip'' (addShip board (Ship ori shipType) pos) (getShipPositions (Ship ori shipType) pos)
                                           | otherwise = True
     where
         prop_addShip'' :: Board -> [Position] -> Bool
         prop_addShip'' _ [] = True
         prop_addShip'' board (x:xs) = getBlock board x == ShipPart && prop_addShip'' board xs

-- returns the size of a ship
shipSize :: ShipType -> Int
shipSize Destroyer = 1
shipSize Submarine = 2
shipSize Cruiser = 3
shipSize Battleship = 4
shipSize Carrier = 5

-- returns the number of hits on a board
nbrOfHits :: Board -> Int
nbrOfHits b = nbrOf b Hit

-- returns the minimum number of hits required to win
nbrOfHitsLeft :: Board -> Int
nbrOfHitsLeft b = nbrOf b ShipPart

-- counts the number of elements of a block type in a board
nbrOf :: Board -> Block -> Int
nbrOf (Board []) block     = 0
nbrOf (Board (x:xs)) block = nbrOf' x block + nbrOf (Board xs) block
    where nbrOf' :: [Block] -> Block -> Int
          nbrOf' xs block = length (filter (== block) xs)

-- prints a game
printGame :: Game -> IO ()
printGame (Game (Board b1) (Board b2)) = putStrLn("-----Your ships----\n"
    ++ printGame' Player b1 ++ "\n----Enemy ships----\n" ++ printGame' Computer b2)
    where printGame' :: Player -> [[Block]] -> String
          printGame' player b = unlines (map (concatMap (printBlock player)) b)
          printBlock :: Player -> Block -> String
          printBlock _ Hit = "x "
          printBlock _ Miss = "0 "
          printBlock _ Water = "~ "
          printBlock _ Swell = "~ "
          printBlock Computer ShipPart = "~ "
          printBlock _ ShipPart = "• "

-- shoots on a position
shoot :: Board -> Position -> Board
shoot b pos = setBlock b pos (shoot'' (getBlock b pos))
    where shoot'' :: Block -> Block
          shoot'' ShipPart = Hit
          shoot'' Hit      = Hit
          shoot'' b        = Miss

-- checks if shot hit ship
isHit :: Board -> Position -> Bool
isHit b p | getBlock b p == Hit = True
          | otherwise = False

-- player computer shoots
computerShoot :: StdGen -> Board -> Board
computerShoot g b = shoot b (computerShoot' g b)
    where computerShoot' :: StdGen -> Board -> Position
          computerShoot' g b = comp'' g b hits
              where hits = listHits b
          comp'' :: StdGen -> Board -> [Position] -> Position
          comp'' g b [] = getRandomPositionUnexplored g b
          comp'' g b (x:xs) | null validPositions = comp'' g b xs
                            | otherwise = head validPositions
              where validPositions = filter isValid pos
                    pos = getPossibleNeighbourShip b x

-- returns a random posisiton unexplored
getRandomPositionUnexplored :: StdGen -> Board -> Position
getRandomPositionUnexplored stdgen board = list !! index
    where list = listUnexplored board
          (index,g2) = randomR (1, length list) stdgen

-- takes a block and a position that is a block of type Hit
-- returns a neighbour that could be a potential ShipPart
getPossibleNeighbourShip :: Board -> Position -> [Position]
getPossibleNeighbourShip b pos = getPossible b (listNeighbours b pos) pos
    where getPossible :: Board -> [(Position, Block)] -> Position -> [Position]
          getPossible b list pos = getPossible' b list pos (countBlock blocks Hit)
              where (p,blocks) = unzip list
          getPossible' :: Board -> [(Position, Block)] -> Position -> Int -> [Position]
          getPossible' _ list _ 0 = getUnknowns list
          getPossible' b list pos 1 | not (isBlockShotAt b opposite) = [opposite]
              where opposite = getOpposite pos (getPositionOfHit list)
          getPossible' _ _ _ _ = []
          -- takes two positions, x and y, returns opposite of y from x
          getOpposite :: Position -> Position -> Position
          getOpposite (Position a b) (Position c d) = Position (a+(a-c)) (b+(b-d))
          -- returns position of Hit
          getPositionOfHit :: [(Position, Block)] -> Position
          getPositionOfHit ((p,Hit):xs) = p
          getPositionOfHit (x:xs) = getPositionOfHit xs
          -- returns positions of unknown blocks
          getUnknowns :: [(Position, Block)] -> [Position]
          getUnknowns [] = []
          getUnknowns ((pos,Hit):xs) = getUnknowns xs
          getUnknowns ((pos,Miss):xs) = getUnknowns xs
          getUnknowns ((pos,block):xs) = pos : getUnknowns xs

-- returns True if block is shot at
isBlockShotAt :: Board -> Position -> Bool
isBlockShotAt b pos | block==Hit || block == Miss = True
                    | otherwise = False
    where block = getBlock b pos

-- counts occurenses of a block in list
countBlock :: [Block] -> Block -> Int
countBlock blocks b = length (filter (==b) blocks)

-- lists positions of blocks that for the player is unexplored (neither of type
-- hit nor miss)
listUnexplored :: Board -> [Position]
listUnexplored b = listPositionsOfBlock b Water
    ++ listPositionsOfBlock b ShipPart
    ++ listPositionsOfBlock b Swell

-- list positions of blocks that are Hit
listHits :: Board -> [Position]
listHits b = listPositionsOfBlock b Hit

-- returns a list of all occurences of a certain block type in a board
listPositionsOfBlock :: Board -> Block -> [Position]
listPositionsOfBlock (Board board) = listPos' 0 board
    where listPos' :: Int -> [[Block]] -> Block -> [Position]
          listPos' _ [] b = []
          listPos' y (row:rows) b = listPos'' 0 y row b ++ listPos' (y+1) rows b
          listPos'' :: Int -> Int -> [Block] -> Block -> [Position]
          listPos'' _ _ [] b = []
          listPos'' x y (block:row) b | block==b = Position x y : listPos'' (x+1) y row b
                                      | otherwise = listPos'' (x+1) y row b

-- list neighbouring blocks of position as a list of tuples (Position,Block)
listNeighbours :: Board -> Position -> [(Position, Block)]
listNeighbours b (Position x y) = getBlockIfValid b (Position (x+1) y)
    ++ getBlockIfValid b (Position (x-1) y)
    ++ getBlockIfValid b (Position x (y+1))
    ++ getBlockIfValid b (Position x (y-1))

-- returns position and block if valid block
getBlockIfValid :: Board -> Position -> [(Position,Block)]
getBlockIfValid b p | isValid p = [(p,getBlock b p)]
                    | otherwise = []

-- checks if position is within game board boundaries
isValid :: Position -> Bool
isValid (Position x y) | x>=0 && x<=9 && y>=0 && y<=9 = True
                       | otherwise = False

-- sets a block to a block type
setBlock :: Board -> Position -> Block -> Board
setBlock (Board b) (Position x y) block = Board (take y b ++ [setBlock' (b !! y) x block] ++ drop (y+1) b)
    where setBlock' :: [Block] -> Int -> Block -> [Block]
          setBlock' b x block = take x b ++ [block] ++ drop (x+1) b

-- returns the block at given position
getBlock :: Board -> Position -> Block
getBlock (Board b) (Position x y) = (b !! y) !! x

-- checks if game is over for any of the players
gameOver :: Game -> Bool
gameOver (Game b1 b2) = boardComplete b1 || boardComplete b2

-- checks if board is complete e.g. no ships left
boardComplete :: Board -> Bool
boardComplete b = nbrOfHitsLeft b == 0

-- returns the winner of the game TODO: error if no player won?
winnerIs :: Game -> Player
winnerIs (Game board1 board2) | boardComplete board1 = Computer
                              | otherwise = Player
