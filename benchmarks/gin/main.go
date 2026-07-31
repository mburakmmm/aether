package main

import (
	"net/http"
	"os"

	"github.com/gin-gonic/gin"
)

type echoIn struct {
	Msg string `json:"msg" binding:"required"`
}

func main() {
	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.GET("/ping", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"pong": true})
	})
	r.POST("/echo", func(c *gin.Context) {
		var in echoIn
		if err := c.ShouldBindJSON(&in); err != nil {
			c.JSON(http.StatusUnprocessableEntity, gin.H{"error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, gin.H{"msg": in.Msg})
	})
	port := os.Getenv("PORT")
	if port == "" {
		port = "3003"
	}
	_ = r.Run(":" + port)
}
